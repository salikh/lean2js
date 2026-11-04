import Lean
import Std.Data.HashMap
import Std.Data.HashSet
import Lean2js.JsUtil

/-!
# Lean IR (λRC) → JavaScript

Input: `Lean.IR.Decl`s of the final IR (explicit reference counting, borrowing, boxing, reset/reuse),
collected from the environment together with everything they reference. See
`docs/design/js-transpiler-ir.md` for the value model. Summary:

* heap objects are JS objects with a reference count `rc` (0 = persistent) so that `isShared`, `reset`
  and the in-place array primitives work exactly as in the native runtime;
* nullary constructors / boxed scalars are plain numbers, `Nat`/`Int`/`UInt64`/`USize` are `BigInt`;
* constructor objects: `{t: cidx, rc, n: #object fields, a0…, u<i>, s<i>_<offset>}`.
-/

namespace Lean2js.CodegenIR

open Lean IR
open Lean2js.JsUtil (mangle declId jsString Tarjan strongConnect)
open Std (HashMap HashSet)

abbrev M := Except String

def vid (x : VarId) : String := s!"x{x.idx}"
def jid (j : JoinPointId) : String := s!"L{j.idx}"
def argStr : Arg → String
  | .var x => vid x
  | .erased => "0"
def argsStr (ys : Array Arg) : String := ", ".intercalate (ys.toList.map argStr)
def listStr (ys : Array Arg) : String := "[" ++ argsStr ys ++ "]"

structure Ctx where
  decls : HashMap Name Decl
  /-- name ↦ (index in tail group, arity) of functions whose saturated tail calls become `continue`. -/
  tail : HashMap Name (Nat × Nat) := {}
  tailSingle : Bool := true
  jps : HashMap Nat (String × Array String) := {}

def isScalarTy : IRType → Bool
  | .float | .float32 | .uint8 | .uint16 | .uint32 | .uint64 | .usize => true
  | _ => false

private def ctorObj (i : CtorInfo) (fields : List String) : String :=
  let fs := (fields.mapIdx fun k a => s!"a{k}: {a}")
  "{" ++ ", ".intercalate (s!"t: {i.cidx}" :: "rc: 1" :: s!"n: {i.size}" :: fs) ++ "}"

def genExpr (ctx : Ctx) (ind : String) (x : VarId) (ty : IRType) : IR.Expr → M String
  | .ctor i ys =>
    if i.size == 0 && i.usize == 0 && i.ssize == 0 then return s!"{ind}const {vid x} = {i.cidx};\n"
    else return s!"{ind}const {vid x} = {ctorObj i (ys.toList.map argStr)};\n"
  | .reset n y => return s!"{ind}const {vid x} = rt.reset({vid y}, {n});\n"
  | .reuse y i updt ys => do
    let v := vid x
    let sets := String.join (ys.toList.mapIdx fun k a => s!"{ind}  {v}.a{k} = {argStr a};\n")
    let tag := if updt then s!"{ind}  {v}.t = {i.cidx};\n" else ""
    return s!"{ind}let {v};\n{ind}if (typeof {vid y} === \"number\") {v} = {ctorObj i (ys.toList.map argStr)};\n"
      ++ s!"{ind}else \{\n{ind}  {v} = {vid y};\n{tag}{ind}  {v}.n = {i.size};\n{sets}{ind}}\n"
  | .proj i y => return s!"{ind}const {vid x} = {vid y}.a{i};\n"
  | .uproj i y => return s!"{ind}const {vid x} = {vid y}.u{i};\n"
  | .sproj n off y => return s!"{ind}const {vid x} = {vid y}.s{n}_{off};\n"
  | .fap c ys => do
    let some d := ctx.decls[c]? | throw s!"unknown function '{c}'"
    unless d.params.size == ys.size do throw s!"arity mismatch in call to '{c}'"
    return s!"{ind}const {vid x} = {declId c.toString}({argsStr ys});\n"
  | .pap c ys => do
    let some d := ctx.decls[c]? | throw s!"unknown function '{c}'"
    return s!"{ind}const {vid x} = rt.pap({declId c.toString}, {d.params.size}, {listStr ys});\n"
  | .ap y ys => return s!"{ind}const {vid x} = rt.ap({vid y}, {listStr ys});\n"
  | .box _ y => return s!"{ind}const {vid x} = {vid y};\n"
  | .unbox y => return s!"{ind}const {vid x} = {vid y};\n"
  | .lit (.str s) => return s!"{ind}const {vid x} = {jsString s};\n"
  | .lit (.num n) =>
    let lit := match ty with
      | .uint8 | .uint16 | .uint32 | .float | .float32 => s!"{n}"
      | _ => s!"{n}n"
    return s!"{ind}const {vid x} = {lit};\n"
  | .isShared y => return s!"{ind}const {vid x} = rt.isShared({vid y});\n"

mutual
partial def genBody (ctx : Ctx) (ind : String) : FnBody → M String
  | .vdecl x ty e b => do
    if let (.fap c ys, .ret (.var r)) := (e, b) then
      if r == x then
        if let some (gi, arity) := ctx.tail[c]? then
          if ys.size == arity then
            let assigns := String.join (ys.toList.mapIdx fun i a => s!"{ind}a{i} = {argStr a};\n")
            let sel := if ctx.tailSingle then "" else s!"{ind}w = {gi};\n"
            return sel ++ assigns ++ s!"{ind}continue _loop;\n"
    return (← genExpr ctx ind x ty e) ++ (← genBody ctx ind b)
  | .jdecl j xs v b => do
    let vars := xs.map (vid ·.x)
    let decl := if vars.isEmpty then "" else s!"{ind}let {", ".intercalate vars.toList};\n"
    let bcode ← genBody { ctx with jps := ctx.jps.insert j.idx (jid j, vars) } (ind ++ "  ") b
    let vcode ← genBody ctx ind v
    return decl ++ s!"{ind}{jid j}: " ++ "{\n" ++ bcode ++ s!"{ind}" ++ "}\n" ++ vcode
  | .set x i y b => return s!"{ind}{vid x}.a{i} = {argStr y};\n" ++ (← genBody ctx ind b)
  | .setTag x c b => return s!"{ind}{vid x}.t = {c};\n" ++ (← genBody ctx ind b)
  | .uset x i y b => return s!"{ind}{vid x}.u{i} = {vid y};\n" ++ (← genBody ctx ind b)
  | .sset x i off y _ b => return s!"{ind}{vid x}.s{i}_{off} = {vid y};\n" ++ (← genBody ctx ind b)
  | .inc x n _ persistent b => do
    let s := if persistent then "" else if n == 1 then s!"{ind}rt.inc({vid x});\n" else s!"{ind}rt.incN({vid x}, {n});\n"
    return s ++ (← genBody ctx ind b)
  | .dec x _ _ persistent b => do
    let s := if persistent then "" else s!"{ind}rt.dec({vid x});\n"
    return s ++ (← genBody ctx ind b)
  | .del _ b => genBody ctx ind b
  | .case _ x xty alts => do
    let sw := if isScalarTy xty then vid x else s!"(typeof {vid x} === \"number\" ? {vid x} : {vid x}.t)"
    let ind2 := ind ++ "  "
    let mut out := s!"{ind}switch ({sw}) " ++ "{\n"
    for a in alts do
      match a with
      | .ctor i b => out := out ++ s!"{ind2}case {i.cidx}: " ++ "{\n" ++ (← genBody ctx (ind2 ++ "  ") b) ++ s!"{ind2}" ++ "}\n"
      | .default b => out := out ++ s!"{ind2}default: " ++ "{\n" ++ (← genBody ctx (ind2 ++ "  ") b) ++ s!"{ind2}" ++ "}\n"
    return out ++ s!"{ind}" ++ "}\n"
  | .ret y => return s!"{ind}return {argStr y};\n"
  | .jmp j ys => do
    let some (label, vars) := ctx.jps[j.idx]? | throw s!"jump to unknown join point {jid j}"
    let assigns := String.join ((vars.zip ys).toList.map fun (v, a) => s!"{ind}{v} = {argStr a};\n")
    return assigns ++ s!"{ind}break {label};\n"
  | .unreachable => return s!"{ind}return rt.unreachable();\n"
end

/-! ## Declarations -/

/-- Names called in saturated tail position. -/
partial def tailCallees (arity : Name → Option Nat) (b : FnBody) (acc : Array Name := #[]) : Array Name :=
  match b with
  | .vdecl x _ (.fap c ys) (.ret (.var r)) => if r == x && arity c == some ys.size then acc.push c else acc
  | .jdecl _ _ v k => tailCallees arity k (tailCallees arity v acc)
  | .case _ _ _ alts => alts.foldl (init := acc) fun acc a => tailCallees arity a.body acc
  | b => if b.isTerminal then acc else tailCallees arity b.body acc

/-- JS wrapper of an extern primitive; also returns the runtime binding `(js name, prim key)` it needs. -/
def genExternWrapper (exports : HashMap String Name) (d : Decl) : String × Option (String × String) :=
  match d with
  | .fdecl .. => ("", none)
  | .extern f ps _ data =>
    let formals := ", ".intercalate (List.range ps.size |>.map (s!"a{·}"))
    let key := match getExternEntryFor data `c with
      | some (.standard _ fn) => fn
      | _ => f.toString
    if let some impl := exports[key]? then
      (s!"function {declId f.toString}({formals}) " ++ "{ " ++ s!"return {declId impl.toString}({formals}); " ++ "}\n", none)
    else
      let binding := mangle "e_" key
      let used := (ps.toList.mapIdx fun i p => (i, p)).filter (fun (_, p) => !(p.ty.isErased || p.ty.isVoid))
        |>.map fun (i, _) => s!"a{i}"
      let body := if ps.isEmpty then s!"return typeof {binding} === \"function\" ? {binding}() : {binding};"
        else s!"return {binding}({", ".intercalate used});"
      (s!"function {declId f.toString}({formals}) " ++ "{ " ++ body ++ " }\n", some (binding, key))

def genFDecl (ctx : Ctx) (d : Decl) : M String := do
  let .fdecl f ps _ body _ := d | throw "internal: extern"
  let fid := declId f.toString
  let n := ps.size
  let ctx := { ctx with tail := {} }
  if n == 0 then
    let b ← genBody ctx "    " body
    return s!"let c_{fid};\nfunction {fid}() " ++ "{\n" ++ s!"  if (c_{fid} === undefined) \{ c_{fid} = (() => " ++ "{\n" ++ b ++ "  })(); rt.persist(c_" ++ fid ++ "); }\n"
      ++ s!"  return c_{fid};\n" ++ "}\n"
  else if (tailCallees (fun g => if g == f then some n else none) body).size > 0 then
    let b ← genBody { ctx with tail := ({} : HashMap Name (Nat × Nat)).insert f (0, n), tailSingle := true } "      " body
    let formals := ", ".intercalate (List.range n |>.map (s!"a{·}"))
    let binds := ", ".intercalate (ps.toList.mapIdx fun i p => s!"{vid p.x} = a{i}")
    return s!"function {fid}({formals}) " ++ "{\n  _loop: while (true) {\n" ++ s!"    const {binds};\n" ++ b ++ "  }\n}\n"
  else
    let b ← genBody ctx "  " body
    let formals := ", ".intercalate (ps.toList.map (vid ·.x))
    return s!"function {fid}({formals}) " ++ "{\n" ++ b ++ "}\n"

def genGroup (ctx : Ctx) (ds : Array Decl) : M String := do
  let maxN := ds.foldl (fun m d => max m d.params.size) 0
  let members : HashMap Name (Nat × Nat) :=
    ds.toList.mapIdx (fun i d => (d.name, (i, d.params.size))) |>.foldl (fun m (k, v) => m.insert k v) {}
  let gctx := { ctx with tail := members, tailSingle := false }
  let name := mangle "g_" ds[0]!.name.toString
  let formals := ", ".intercalate ("w" :: (List.range maxN).map (s!"a{·}"))
  let mut cases := ""
  for (d, i) in ds.toList.zip (List.range ds.size) do
    let .fdecl _ ps _ body _ := d | throw "internal: extern in group"
    let b ← genBody gctx "        " body
    let binds := ps.toList.mapIdx fun j p => s!"          const {vid p.x} = a{j};\n"
    cases := cases ++ s!"      case {i}: " ++ "{\n" ++ String.join binds ++ b ++ "      }\n"
  let mut out := s!"function {name}({formals}) " ++ "{\n  _loop: while (true) {\n    switch (w) {\n" ++ cases ++ "    }\n  }\n}\n"
  for (d, i) in ds.toList.zip (List.range ds.size) do
    let ps := (List.range d.params.size).map (s!"a{·}")
    out := out ++ s!"function {declId d.name.toString}({", ".intercalate ps}) " ++ "{ "
      ++ s!"return {name}({", ".intercalate (toString i :: ps)}); " ++ "}\n"
  return out

/-- Groups (size ≥ 2) of functions calling each other in saturated tail position. -/
def tailGroups (decls : HashMap Name Decl) (kept : Array Decl) : Array (Array Decl) := Id.run do
  let cand := kept.filter fun d => d.params.size > 0 && !d.isExtern
  let idxOf : HashMap Name Nat := cand.foldl (init := {}) fun m d => m.insert d.name m.size
  let arity (g : Name) : Option Nat :=
    match decls[g]? with
    | some d => if d.params.size > 0 && !d.isExtern && idxOf.contains g then some d.params.size else none
    | none => none
  let adj := cand.map fun d =>
    match d with
    | .fdecl _ _ _ b _ => (tailCallees arity b).filterMap (idxOf[·]?)
    | _ => #[]
  let n := cand.size
  let init : Tarjan :=
    { index := Array.replicate n none
      low := Array.replicate n 0
      onStack := Array.replicate n false }
  let st := (do for v in List.range n do
                  if (← get).index[v]!.isNone then strongConnect adj v : StateM Tarjan Unit).run init |>.2
  return st.sccs.filter (·.size > 1) |>.map (·.reverse.map (cand[·]!))

/-! ## Collecting the program -/

structure Collected where
  decls : Array Decl
  exports : HashMap String Name

private partial def bodyRefs (b : FnBody) (acc : Array Name) : Array Name :=
  match b with
  | .vdecl _ _ e k =>
    let acc := match e with | .fap c _ | .pap c _ => acc.push c | _ => acc
    bodyRefs k acc
  | .jdecl _ _ v k => bodyRefs k (bodyRefs v acc)
  | .case _ _ _ alts => alts.foldl (init := acc) fun acc a => bodyRefs a.body acc
  | b => if b.isTerminal then acc else bodyRefs b.body acc

/-- IR declarations reachable from `roots` (names), following `fap`/`pap` and `@[export]` implementations of
extern primitives. -/
def collect (env : Environment) (roots : Array Name) : Collected := Id.run do
  let exportIndex : HashMap String Name := env.constants.fold (init := {}) fun m n _ =>
    match getExportNameFor? env n with
    | some e => m.insert e.toString n
    | none => m
  let mut work := roots
  let mut seen : HashSet Name := {}
  let mut decls : Array Decl := #[]
  while work.size > 0 do
    let n := work.back!
    work := work.pop
    if seen.contains n then continue
    seen := seen.insert n
    let some d := findEnvDecl env n | continue
    decls := decls.push d
    match d with
    | .fdecl _ _ _ b _ =>
      for c in bodyRefs b #[] do unless seen.contains c do work := work.push c
    | .extern _ _ _ data =>
      if let some (.standard _ fn) := getExternEntryFor data `c then
        if let some impl := exportIndex[fn]? then work := work.push impl
  return { decls := decls.qsort (fun a b => a.name.toString < b.name.toString), exports := exportIndex }

/-! ## Program -/

structure Options where
  runtime : String := "./lean_rt.js"
  run : Bool := false
  all : Bool := false

def genProgram (env : Environment) (fileName : String) (opts : Options) : M (String × Array Decl) := do
  let localDecls := (getDecls env).toArray.map (·.name)
  let roots :=
    if opts.all || (findEnvDecl env `main).isNone then localDecls else #[`main]
  let c := collect env (roots.push `IO.Error.toString)
  let decls : HashMap Name Decl := c.decls.foldl (fun m d => m.insert d.name d) {}
  let ctx : Ctx := { decls }
  let groups := tailGroups decls c.decls
  let mut grouped : HashSet Name := {}
  let mut body := ""
  for g in groups do
    for d in g do grouped := grouped.insert d.name
    body := body ++ (← genGroup ctx g)
  let mut externCode := ""
  let mut externBinds : Array (String × String) := #[]
  for d in c.decls do
    if grouped.contains d.name then continue
    match d with
    | .extern .. =>
      let (code, bind?) := genExternWrapper c.exports d
      externCode := externCode ++ code
      if let some bk := bind? then
        unless externBinds.any (·.1 == bk.1) do externBinds := externBinds.push bk
    | .fdecl .. => body := body ++ (← genFDecl ctx d)
  let header := s!"// Generated by lean2js (IR backend) from {fileName}. Do not edit.\n"
    ++ s!"import * as rt from {jsString opts.runtime};\n"
  let bindStr := String.join (externBinds.toList.map fun (b, key) =>
    s!"const {b} = rt.prims[{jsString key}] ?? rt.missing({jsString key});\n")
  let mainDecl := decls[`main]?
  let exports := match mainDecl with
    | some d => s!"export \{ {declId "main"} as main };\nexport const mainArity = {d.params.size};\n"
    | none => ""
  let errHook := if decls.contains `IO.Error.toString then s!"rt.setErrorToString({declId "IO.Error.toString"});\n" else ""
  let run := match mainDecl with
    | some d => if opts.run then s!"rt.runMain({declId "main"}, {d.params.size});\n" else ""
    | none => ""
  return (header ++ bindStr ++ "\n" ++ externCode ++ body ++ "\n" ++ exports ++ errHook ++ run, c.decls)

end Lean2js.CodegenIR

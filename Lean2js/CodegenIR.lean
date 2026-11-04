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
  /-- constants with an `[init]`/`[builtin_init]` function: value = result of running that `IO` action (lazily, once). -/
  initFns : HashMap Name Name := {}
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
  -- Scalar fields of objects loaded from .olean files are decoded lazily from the raw bytes (`rt.sget`/`rt.uget`), see lean_olean.js.
  | .uproj i y => return s!"{ind}const {vid x} = {vid y}.u{i} ?? rt.uget({vid y}, {i});\n"
  | .sproj n off y =>
    let code := match ty with
      | .uint8 => 1 | .uint16 => 2 | .uint32 => 4 | .uint64 => 8 | .float => 9 | .float32 => 10 | _ => 8
    return s!"{ind}const {vid x} = {vid y}.s{n}_{off} ?? rt.sget({vid y}, {n}, {off}, {code});\n"
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
def genExternWrapper (exports : HashMap String Name) (decls : HashMap Name Decl) (d : Decl) : String × Option (String × String) :=
  match d with
  | .fdecl .. => ("", none)
  | .extern f ps _ data =>
    let formals := ", ".intercalate (List.range ps.size |>.map (s!"a{·}"))
    let key := match getExternEntryFor data `c with
      | some (.standard _ fn) => fn
      | _ => f.toString
    if let some impl := exports[key]? then
      -- `@[export]` implementations take owned parameters, the extern declaration may borrow (`@&`): adapt the reference counts
      let implPs := match decls[impl]? with | some i => i.params | none => ps
      let pairs := ps.toList.zip implPs.toList |>.mapIdx fun i (e, m) => (i, e.borrow, m.borrow)
      let incs := String.join <| pairs.filterMap fun (i, eb, mb) => if eb && !mb then some s!"rt.inc(a{i}); " else none
      let decsAfter := String.join <| pairs.filterMap fun (i, eb, mb) => if !eb && mb then some s!" rt.dec(a{i});" else none
      let call := s!"{declId impl.toString}({formals})"
      let body := if decsAfter.isEmpty then s!"{incs}return {call};" else s!"{incs}const r = {call};{decsAfter} return r;"
      (s!"function {declId f.toString}({formals}) " ++ "{ " ++ body ++ " }\n", none)
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
    let b ← match ctx.initFns[f]? with
      | some initFn => pure s!"    return rt.runInit({declId initFn.toString}, {jsString f.toString});\n"
      | none => genBody ctx "    " body
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

/-- `@[export sym]` symbol ↦ implementing declaration, for all constants of `env`. -/
def mkExportIndex (env : Environment) : HashMap String Name :=
  env.constants.fold (init := {}) fun m n _ =>
    match getExportNameFor? env n with
    | some e => m.insert e.toString n
    | none => m

/-- Exported Lean functions that the JS runtime calls itself (constructors of `Expr`/`Level`/`Name`, which the native
runtime's C++ code calls through their `@[export]` symbols); registered as `rt.exports[symbol]`. -/
def runtimeExportPrefixes : Array String := #["lean_expr_mk_", "lean_level_mk_", "lean_name_mk_", "lean_get_lmvar_", "lean_get_mvar_", "lean_get_delayed_mvar_",
    "lean_assign_lmvar", "lean_assign_mvar"]

/-- IR declarations reachable from `roots` (names), following `fap`/`pap` and `@[export]` implementations of
extern primitives. -/
def collect (env : Environment) (roots : Array Name) (exportIndex : HashMap String Name) : Collected := Id.run do
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
    | .fdecl _ ps _ b _ =>
      if ps.isEmpty then
        if let some i := getInitFnNameFor? env n then work := work.push i
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
  /-- run the `[init]`/`[builtin_init]` declarations of *all* imported modules at startup (what the native `main` does via
  `initialize_<Module>`); otherwise only those of the main module, plus lazily the constants reachable from `main`. -/
  initAll : Bool := false

/-- Order key of an initializer: (module index, `_hyg` counter of the init function's name, name). Imported oleans do not record
declaration order, but the macro-scope counter grows with source position. -/
partial def hygNum : Name → Nat
  | .num (.str _ "_hyg") k => k
  | .num p _ => hygNum p
  | .str p _ => hygNum p
  | _ => 0

/-- Declarations to run at startup, in order: IO-unit init functions, and (with `all`) constants with an init function. -/
def initOrder (env : Environment) (all : Bool) : Array Name := Id.run do
  let nmods := env.header.moduleNames.size
  let cands : Array Name :=
    if all then env.constants.fold (init := #[]) fun acc n _ =>
      if isIOUnitInitFn env n || (getInitFnNameFor? env n).isSome then acc.push n else acc
    else (getDecls env).toArray.map (·.name) |>.filter (isIOUnitInitFn env)
  -- within a module: explicit `initialize` blocks (by macro-scope counter) before the `_regBuiltin` registrations generated for
  -- `@[builtin_…]` attributes (e.g. a parser category must be registered before the parsers that use it)
  let key (n : Name) : Nat × Nat × String :=
    let fn := if isIOUnitInitFn env n then n else (getInitFnNameFor? env n).getD n
    let reg := fn.components.any (· == `_regBuiltin)
    ((env.getModuleIdxFor? n).map (·.toNat) |>.getD nmods, (if reg then 1 <<< 40 else 0) + hygNum fn, n.toString)
  let keyed := cands.map fun n => (key n, n)
  let sorted := keyed.qsort fun a b =>
    a.1.1 < b.1.1 || (a.1.1 == b.1.1 && (a.1.2.1 < b.1.2.1 || (a.1.2.1 == b.1.2.1 && a.1.2.2 < b.1.2.2)))
  return sorted.map (·.2)

def genProgram (env : Environment) (fileName : String) (opts : Options) : M (String × Array Decl) := do
  let localDecls := (getDecls env).toArray.map (·.name)
  let roots :=
    if opts.all || (findEnvDecl env `main).isNone then localDecls else #[`main]
  let exportIndex := mkExportIndex env
  let rtExports := exportIndex.toArray.filter fun (sym, _) => runtimeExportPrefixes.any (sym.startsWith ·)
  let inits := initOrder env opts.initAll
  let c := collect env ((roots.push `IO.Error.toString) ++ rtExports.map (·.2) ++ inits) exportIndex
  let decls : HashMap Name Decl := c.decls.foldl (fun m d => m.insert d.name d) {}
  let initFns : HashMap Name Name := c.decls.foldl (init := {}) fun m d =>
    match d with
    | .fdecl n ps .. => if ps.isEmpty then (match getInitFnNameFor? env n with | some i => m.insert n i | none => m) else m
    | _ => m
  let ctx : Ctx := { decls, initFns }
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
      let (code, bind?) := genExternWrapper c.exports decls d
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
  let rtExportReg := String.join <| (rtExports.qsort (fun a b => a.1 < b.1)).toList.filterMap fun (sym, n) =>
    if decls.contains n then some s!"rt.exports[{jsString sym}] = {declId n.toString};\n" else none
  let initCalls := String.join <| inits.toList.filterMap fun n =>
    match decls[n]? with
    | some d =>
      if d.isExtern then none
      else if d.params.isEmpty then some s!"  () => \{ {declId n.toString}(); return null; },\n"
      else some s!"  () => {declId n.toString}(0),\n"
    | none => none
  let initFn := if initCalls.isEmpty then "" else
    "const initSteps = [\n" ++ initCalls ++ "];\nexport function initialize() { return rt.runInitSteps(initSteps); }\nrt.setInit(initialize);\n"
  let run := match mainDecl with
    | some d => if opts.run then s!"rt.runMain({declId "main"}, {d.params.size});\n" else ""
    | none => ""
  return (header ++ bindStr ++ "\n" ++ externCode ++ body ++ "\n" ++ exports ++ errHook ++ rtExportReg ++ initFn ++ run, c.decls)

end Lean2js.CodegenIR

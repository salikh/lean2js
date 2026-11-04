import Std.Data.HashMap
import Std.Data.HashSet
import Lean2js.Ast

/-!
# LCNF (mono, JSON) → JavaScript

See `docs/design/js-transpiler.md` for the value representation and the mapping.
Summary:
* every Lean declaration `f` becomes `function l_f(params…)`; zero-parameter declarations are memoized;
* primitives (`extern`) become wrapper functions delegating to `rt.<c symbol>`;
* join points become labeled blocks (`break`), self tail calls become `while(true)` loops;
* constructors with fields are `{t: cidx, a0: …, a1: …}`, constructors of enumeration-like types are
  the `cidx` number; `Nat`/`Int` are `BigInt`.
-/

namespace Lean2js.Codegen

open Lean2js.Ast
open Std (HashMap HashSet)

/-! ## Names -/

private def isIdentChar (c : Char) : Bool := c.isAlphanum && c.toNat < 128 || c == '_'

/-- Mangle a (dotted) Lean name into a valid JS identifier. -/
def mangle (prefix_ : String) (s : String) : String :=
  s.foldl (init := prefix_) fun acc c =>
    if isIdentChar c then acc.push c
    else if c == '.' then acc.push '$'
    else acc ++ s!"$u{String.ofList (Nat.toDigits 16 c.toNat)}_"

/-- JS identifier of a Lean declaration. -/
def declId (n : String) : String := mangle "l_" n

/-- JS identifier of a local variable (`_uniq.12.3` ↦ `v12_3`). -/
def varId (id : String) : String :=
  let id := if id.startsWith "_uniq." then (id.drop 6).toString else id
  mangle "v" (id.map fun c => if c == '.' then '_' else c)

def jsString (s : String) : String := (Lean.Json.str s).compress

/-! ## Context -/

structure Ctx where
  decls : HashMap String Decl
  /-- constructor name ↦ (constructor, is the type enumeration-like) -/
  ctors : HashMap String (Ctor × Bool)
  /-- inductive name ↦ is enumeration-like -/
  enums : HashMap String Bool
  /-- current declaration if self tail calls should be compiled to `continue` -/
  self : Option (String × Nat) := none
  /-- join point id ↦ (label, parameter variables) -/
  jps : HashMap String (String × Array String) := {}

abbrev M := Except String

def argStr : Arg → String
  | .erased => "0"
  | .fvar id => varId id

def argsStr (args : Array Arg) : String := ", ".intercalate (args.toList.map argStr)

def litStr : Lit → String
  | .nat n => s!"{n}n"
  | .str s => jsString s
  | .small n => s!"{n}"
  | .big n => s!"{n}n"

/-! ## Expressions -/

private def genCtor (ctx : Ctx) (name : String) (args : Array Arg) : M String := do
  match name with
  | "Nat.zero" => return "0n"
  | "Nat.succ" => return s!"({argStr args[0]!} + 1n)"
  | "Int.ofNat" => return argStr args[0]!
  | "Int.negSucc" => return s!"(-{argStr args[0]!} - 1n)"
  | _ =>
    let some (c, isEnum) := ctx.ctors[name]?
      | throw s!"unknown constructor or constant '{name}'"
    if isEnum then return s!"{c.cidx}"
    if args.size != c.numFields then
      throw s!"constructor {name}: expected {c.numFields} fields, got {args.size} arguments"
    let fields := (args.toList.mapIdx fun i a => s!"a{i}: {argStr a}")
    return "{" ++ ", ".intercalate (s!"t: {c.cidx}" :: fields) ++ "}"

def genVal (ctx : Ctx) : LetVal → M String
  | .lit l => return litStr l
  | .erased => return "0"
  | .proj _ idx s => return s!"{varId s}.a{idx}"
  | .app f args => return s!"rt.ap({varId f}, [{argsStr args}])"
  | .const n args =>
    match ctx.decls[n]? with
    | some d =>
      let ar := d.params.size
      let f := declId n
      if args.size == ar then return s!"{f}({argsStr args})"
      else if args.size < ar then return s!"rt.pap({f}, {ar}, [{argsStr args}])"
      else
        let first := args.extract 0 ar
        let rest := args.extract ar args.size
        return s!"rt.ap({f}({argsStr first}), [{argsStr rest}])"
    | none => genCtor ctx n args

/-! ## Statements -/

/-- Does `c` contain a self tail call `let x := self args; return x` (not looking inside `fun` bodies)? -/
partial def hasSelfTail (self : String) (arity : Nat) : Code → Bool
  | .let id (.const n args) (.ret r) => n == self && args.size == arity && r == id
  | .let _ _ k | .fun_ _ k => hasSelfTail self arity k
  | .jp (.mk _ _ b) k => hasSelfTail self arity b || hasSelfTail self arity k
  | .cases _ _ alts => alts.any fun a =>
    match a with
    | .alt _ _ b | .default b => hasSelfTail self arity b
  | _ => false

private def jpLabel (id : String) : String := "L" ++ ((varId id).drop 1).toString

private def bindFields (ind : String) (d : String) (ps : Array Param) : String :=
  String.join (ps.toList.mapIdx fun i p => s!"{ind}const {varId p.id} = {d}.a{i};\n")

mutual
partial def genCode (ctx : Ctx) (ind : String) : Code → M String
  | .let id val k => do
    -- self tail call → loop
    if let (.const n args, .ret r, some (self, arity)) := (val, k, ctx.self) then
      if n == self && args.size == arity && r == id then
        let assigns := String.join (args.toList.mapIdx fun i a => s!"{ind}a{i} = {argStr a};\n")
        return assigns ++ s!"{ind}continue _loop;\n"
    let e ← genVal ctx val
    return s!"{ind}const {varId id} = {e};\n" ++ (← genCode ctx ind k)
  | .fun_ (.mk id ps body) k => do
    let params := ", ".intercalate (ps.toList.map (varId ·.id))
    let b ← genCode { ctx with self := none, jps := {} } (ind ++ "  ") body
    let s := s!"{ind}const {varId id} = rt.mkClo(({params}) => " ++ "{\n" ++ b ++ s!"{ind}"
      ++ "}" ++ s!", {ps.size});\n"
    return s ++ (← genCode ctx ind k)
  | .jp (.mk id ps body) k => do
    let label := jpLabel id
    let vars := ps.map (varId ·.id)
    let decl := if vars.isEmpty then "" else s!"{ind}let {", ".intercalate vars.toList};\n"
    let kcode ← genCode { ctx with jps := ctx.jps.insert id (label, vars) } (ind ++ "  ") k
    let bcode ← genCode ctx ind body
    return decl ++ s!"{ind}{label}: " ++ "{\n" ++ kcode ++ s!"{ind}" ++ "}\n" ++ bcode
  | .jmp j args => do
    let some (label, vars) := ctx.jps[j]? | throw s!"jump to unknown join point {j}"
    let assigns := String.join ((vars.zip args).toList.map fun (v, a) => s!"{ind}{v} = {argStr a};\n")
    return assigns ++ s!"{ind}break {label};\n"
  | .ret v => return s!"{ind}return {varId v};\n"
  | .unreach => return s!"{ind}return rt.unreachable();\n"
  | .cases ty discr alts => genCases ctx ind ty discr alts

partial def genCases (ctx : Ctx) (ind : String) (ty discr : String) (alts : Array Alt) : M String := do
  let d := varId discr
  let ind2 := ind ++ "  "
  match ty with
  | "Nat" | "Int" =>
    -- BigInt based: if-chain
    let mut out := ""
    let mut first := true
    let mut dflt := none
    for a in alts do
      match a with
      | .default b => dflt := some b
      | .alt c ps b =>
        let (cond, binds) := match c with
          | "Nat.zero" => (s!"{d} === 0n", "")
          | "Nat.succ" => (s!"{d} !== 0n", s!"{ind2}const {varId ps[0]!.id} = {d} - 1n;\n")
          | "Int.ofNat" => (s!"{d} >= 0n", s!"{ind2}const {varId ps[0]!.id} = {d};\n")
          | _ => (s!"{d} < 0n", s!"{ind2}const {varId ps[0]!.id} = -{d} - 1n;\n")
        let kw := if first then "if" else " else if"
        out := out ++ (if first then ind else "") ++ s!"{kw} ({cond}) " ++ "{\n" ++ binds ++ (← genCode ctx ind2 b)
          ++ s!"{ind}" ++ "}"
        first := false
    if let some b := dflt then
      out := out ++ (if first then "" else " else ") ++ "{\n" ++ (← genCode ctx ind2 b) ++ s!"{ind}" ++ "}"
    return out ++ "\n"
  | _ =>
    let some isEnum := ctx.enums[ty]?
      | throw s!"cases on type '{ty}' without constructor metadata (unsupported builtin type?)"
    let sw := if isEnum then d else s!"{d}.t"
    let mut out := s!"{ind}switch ({sw}) " ++ "{\n"
    for a in alts do
      match a with
      | .default b =>
        out := out ++ s!"{ind2}default: " ++ "{\n" ++ (← genCode ctx (ind2 ++ "  ") b) ++ s!"{ind2}" ++ "}\n"
      | .alt c ps b =>
        let some (ct, _) := ctx.ctors[c]? | throw s!"unknown constructor {c} in cases"
        out := out ++ s!"{ind2}case {ct.cidx}: " ++ "{\n" ++ bindFields (ind2 ++ "  ") d ps
          ++ (← genCode ctx (ind2 ++ "  ") b) ++ s!"{ind2}" ++ "}\n"
    return out ++ s!"{ind}" ++ "}\n"
end

/-! ## Declarations -/

structure Out where
  externs : Array (String × String) := #[]   -- (js binding, runtime key)
  code : String := ""

/-- Function wrapping an extern primitive. -/
def genExtern (d : Decl) (fn : Option String) : String × String × String :=
  let key := fn.getD d.name
  let binding := mangle "e_" key
  let ps := d.params
  let params := ", ".intercalate (ps.toList.mapIdx fun i _ => s!"a{i}")
  let used := (ps.toList.mapIdx fun i p => (i, p)).filter (·.2.type != "lcErased") |>.map fun (i, _) => s!"a{i}"
  let body :=
    if ps.isEmpty then s!"return typeof {binding} === \"function\" ? {binding}() : {binding};"
    else s!"return {binding}({", ".intercalate used});"
  (binding, key, s!"function {declId d.name}({params}) " ++ "{ " ++ body ++ " }\n")

def genDecl (ctx : Ctx) (d : Decl) : M String := do
  let .code body := d.value | throw "internal: extern"
  let f := declId d.name
  let n := d.params.size
  if n == 0 then
    let b ← genCode { ctx with self := none } "    " body
    return s!"let c_{f};\nfunction {f}() " ++ "{\n" ++ s!"  if (c_{f} === undefined) c_{f} = (() => " ++ "{\n" ++ b ++ "  })();\n"
      ++ s!"  return c_{f};\n" ++ "}\n"
  else if hasSelfTail d.name n body then
    let b ← genCode { ctx with self := some (d.name, n) } "      " body
    let formals := ", ".intercalate (List.range n |>.map (s!"a{·}"))
    let binds := ", ".intercalate (d.params.toList.mapIdx fun i p => s!"{varId p.id} = a{i}")
    return s!"function {f}({formals}) " ++ "{\n  _loop: while (true) {\n" ++ s!"    const {binds};\n" ++ b
      ++ "  }\n}\n"
  else
    let b ← genCode { ctx with self := none } "  " body
    let formals := ", ".intercalate (d.params.toList.map (varId ·.id))
    return s!"function {f}({formals}) " ++ "{\n" ++ b ++ "}\n"

/-! ## Reachability -/

partial def codeConsts (c : Code) (acc : Array String) : Array String :=
  match c with
  | .let _ v k =>
    let acc := match v with | .const n _ => acc.push n | _ => acc
    codeConsts k acc
  | .fun_ (.mk _ _ b) k | .jp (.mk _ _ b) k => codeConsts k (codeConsts b acc)
  | .cases _ _ alts => alts.foldl (init := acc) fun acc a =>
    match a with
    | .alt _ _ b | .default b => codeConsts b acc
  | _ => acc

def reachable (decls : HashMap String Decl) (roots : Array String) : HashSet String := Id.run do
  let mut seen : HashSet String := {}
  let mut work := roots
  while work.size > 0 do
    let n := work.back!
    work := work.pop
    if seen.contains n then continue
    seen := seen.insert n
    if let some d := decls[n]? then
      if let .code b := d.value then
        for c in codeConsts b #[] do
          unless seen.contains c do work := work.push c
  return seen

/-! ## Program -/

structure Options where
  /-- Path of the runtime module as imported from the generated file. -/
  runtime : String := "./lean_runtime.js"
  /-- Names of exported entry points; defaults to `main` if it exists, else all local declarations. -/
  roots : Array String := #[]
  /-- Append a call running `main` (Node). -/
  run : Bool := false
  /-- Keep all declarations, no tree shaking. -/
  all : Bool := false

def genProgram (p : Program) (opts : Options) : M String := do
  let decls : HashMap String Decl := p.decls.foldl (fun m d => m.insert d.name d) {}
  let mut ctors : HashMap String (Ctor × Bool) := {}
  let mut enums : HashMap String Bool := {}
  for i in p.inductives do
    let isEnum := i.ctors.all (·.numFields == 0)
    enums := enums.insert i.name isEnum
    for c in i.ctors do ctors := ctors.insert c.name (c, isEnum)
  let ctx : Ctx := { decls, ctors, enums }
  let roots :=
    if !opts.roots.isEmpty then opts.roots
    else if decls.contains "main" then #["main"]
    else (p.decls.filter (·.module.isNone)).map (·.name)
  let keep := if opts.all then (HashSet.ofList (p.decls.toList.map (·.name))) else reachable decls roots
  let mut externBindings : Array (String × String) := #[]
  let mut seenBinding : HashSet String := {}
  let mut body := ""
  for d in p.decls do
    unless keep.contains d.name do continue
    match d.value with
    | .extern fn =>
      let (b, key, code) := genExtern d fn
      unless seenBinding.contains b do
        seenBinding := seenBinding.insert b
        externBindings := externBindings.push (b, key)
      body := body ++ code
    | .code _ => body := body ++ (← genDecl ctx d)
  let header := s!"// Generated by lean2js from {p.file}. Do not edit.\n"
    ++ s!"import * as rt from {jsString opts.runtime};\n"
  let binds := String.join (externBindings.toList.map fun (b, key) =>
    s!"const {b} = rt[{jsString key}] ?? rt.missing({jsString key});\n")
  let exports := String.join (roots.toList.filterMap fun r =>
    if keep.contains r && decls.contains r then some s!"export \{ {declId r} as {mangle "" r} };\n" else none)
  let run :=
    if opts.run then
      match decls["main"]? with
      | some d => s!"rt.runMain({declId "main"}, {d.params.size});\n"
      | none => ""
    else ""
  return header ++ binds ++ "\n" ++ body ++ "\n" ++ exports ++ run

end Lean2js.Codegen

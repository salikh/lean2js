import Lean.Data.Json

/-!
# LCNF dump AST (pure phase subset) and JSON decoding

Input of the transpiler. Mirrors the schema in `docs/design/lcnf-json.md`
(`mono` phase, produced by `lcnf-dump --with-deps`). Types are not kept except
for parameters (to find erased parameters of externs).
-/

namespace Lean2js.Ast

open Lean

inductive Arg where
  | erased
  | fvar (id : String)
  deriving Inhabited

inductive Lit where
  | nat (n : Nat)
  | str (s : String)
  /-- `UInt8`/`UInt16`/`UInt32` (JS number) -/
  | small (n : Nat)
  /-- `UInt64`/`USize` (JS BigInt) -/
  | big (n : Nat)
  deriving Inhabited

structure Param where
  id : String
  name : String
  type : String
  deriving Inhabited

inductive LetVal where
  | lit (l : Lit)
  | erased
  | proj (typeName : String) (idx : Nat) (struct : String)
  | const (name : String) (args : Array Arg)
  | app (fn : String) (args : Array Arg)
  deriving Inhabited

mutual
inductive Code where
  | let (id : String) (val : LetVal) (k : Code)
  | fun_ (d : FunDecl) (k : Code)
  | jp (d : FunDecl) (k : Code)
  | jmp (jp : String) (args : Array Arg)
  | cases (typeName : String) (discr : String) (alts : Array Alt)
  | ret (v : String)
  | unreach
  deriving Inhabited

inductive FunDecl where
  | mk (id : String) (params : Array Param) (body : Code)
  deriving Inhabited

inductive Alt where
  | alt (ctor : String) (params : Array Param) (body : Code)
  | default (body : Code)
  deriving Inhabited
end

inductive DeclValue where
  | code (body : Code)
  /-- extern primitive; `fn` is the C symbol of the first `standard` entry for backend `all`/`c`. -/
  | extern (fn : Option String)
  deriving Inhabited

structure Decl where
  name : String
  /-- defining module; `none` for declarations of the transpiled file -/
  module : Option String := none
  /-- C symbol of an `@[export]` attribute, if any -/
  export_ : Option String := none
  params : Array Param
  value : DeclValue
  deriving Inhabited

structure Ctor where
  name : String
  cidx : Nat
  numParams : Nat
  numFields : Nat
  deriving Inhabited

structure Inductive where
  name : String
  ctors : Array Ctor
  deriving Inhabited

structure Program where
  file : String
  decls : Array Decl
  inductives : Array Inductive
  missing : Array String
  deriving Inhabited

/-! ## Decoding -/

abbrev P := Except String

private def str (j : Json) (k : String) : P String := j.getObjValAs? String k
private def nat (j : Json) (k : String) : P Nat := j.getObjValAs? Nat k
private def arr (j : Json) (k : String) : P (Array Json) := j.getObjValAs? (Array Json) k
private def obj (j : Json) (k : String) : P Json := j.getObjVal? k

def parseArg (j : Json) : P Arg := do
  match ← str j "kind" with
  | "fvar" => return .fvar (← str j "id")
  | _ => return .erased

def parseArgs (j : Json) (k : String) : P (Array Arg) := do (← arr j k).mapM parseArg

def parseParam (j : Json) : P Param :=
  return { id := ← str j "id", name := ← str j "name", type := ← str j "type" }

def parseParams (j : Json) : P (Array Param) := do (← arr j "params").mapM parseParam

def parseLit (j : Json) : P Lit := do
  match ← str j "kind" with
  | "nat" => return .nat (← nat j "value")
  | "str" => return .str (← str j "value")
  | "uint8" | "uint16" | "uint32" => return .small (← nat j "value")
  | "uint64" | "usize" => return .big (← nat j "value")
  | k => throw s!"unknown literal kind {k}"

def parseLetVal (j : Json) : P LetVal := do
  match ← str j "kind" with
  | "lit" => return .lit (← parseLit (← obj j "lit"))
  | "erased" => return .erased
  | "proj" => return .proj (← str j "typeName") (← nat j "idx") (← str j "struct")
  | "const" => return .const (← str j "name") (← parseArgs j "args")
  | "app" => return .app (← str j "fn") (← parseArgs j "args")
  | k => throw s!"unsupported let value kind '{k}' (only the mono phase is supported)"

mutual
partial def parseCode (j : Json) : P Code := do
  match ← str j "kind" with
  | "let" => return .let (← str j "id") (← parseLetVal (← obj j "value")) (← parseCode (← obj j "body"))
  | "fun" => return .fun_ (← parseFunDecl (← obj j "decl")) (← parseCode (← obj j "body"))
  | "jp" => return .jp (← parseFunDecl (← obj j "decl")) (← parseCode (← obj j "body"))
  | "jmp" => return .jmp (← str j "jp") (← parseArgs j "args")
  | "cases" =>
    return .cases (← str j "typeName") (← str j "discr") (← (← arr j "alts").mapM parseAlt)
  | "return" => return .ret (← str j "var")
  | "unreach" => return .unreach
  | k => throw s!"unsupported code kind '{k}'"

partial def parseFunDecl (j : Json) : P FunDecl :=
  return .mk (← str j "id") (← parseParams j) (← parseCode (← obj j "body"))

partial def parseAlt (j : Json) : P Alt := do
  match ← str j "kind" with
  | "alt" => return .alt (← str j "ctor") (← parseParams j) (← parseCode (← obj j "body"))
  | "default" => return .default (← parseCode (← obj j "body"))
  | k => throw s!"unsupported alt kind '{k}'"
end

def parseDecl (j : Json) : P Decl := do
  let value ← obj j "value"
  let v ← match ← str value "kind" with
    | "code" => pure (DeclValue.code (← parseCode (← obj value "body")))
    | "extern" =>
      let entries ← arr value "entries"
      let mut fn := none
      for e in entries do
        if fn.isNone && (← str e "kind") == "standard" then
          let b ← str e "backend"
          if b == "all" || b == "c" then fn := some (← str e "fn")
      pure (DeclValue.extern fn)
    | k => throw s!"unknown decl value kind {k}"
  let module := match j.getObjVal? "module" with
    | .ok (.str m) => some m
    | _ => none
  let export_ := match j.getObjVal? "export" with
    | .ok (.str m) => some m
    | _ => none
  return { name := ← str j "name", module, export_, params := ← parseParams j, value := v }

def parseInductive (j : Json) : P Inductive := do
  let ctors ← (← arr j "ctors").mapM fun c =>
    return ({ name := ← str c "name", cidx := ← nat c "cidx", numParams := ← nat c "numParams", numFields := ← nat c "numFields" } : Ctor)
  return { name := ← str j "name", ctors }

def parseProgram (j : Json) : P Program := do
  let phase ← str j "phase"
  unless phase == "mono" do throw s!"expected phase 'mono', got '{phase}'"
  let decls ← (← arr j "decls").mapM parseDecl
  let inductives ← (← arr j "inductives").mapM parseInductive
  let missing ← (← arr j "missing").mapM fun m => m.getStr?
  return { file := ← str j "file", decls, inductives, missing }

end Lean2js.Ast

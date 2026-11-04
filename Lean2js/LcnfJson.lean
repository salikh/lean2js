import Lean

/-!
# LCNF → JSON

Serialization of Lean's LCNF (`Lean.Compiler.LCNF`) to JSON. Schema is described in
`docs/design/lcnf-json.md`. Decisions (see `docs/tickets/lcnf-*.md`):
types are strings, names are dotted strings, free variables are their `FVarId` names.
-/

namespace Lean2js.LcnfJson

open Lean Lean.Compiler Lean.Compiler.LCNF

/-- Schema version, bump on any incompatible change. -/
def schemaVersion : Nat := 1

def nameToJson (n : Name) : Json := Json.str n.toString

def fvarToJson (f : FVarId) : Json := nameToJson f.name

/-- Types are rendered as strings. -/
def typeToJson (e : Expr) : Json := Json.str (toString e)

def obj (kind : String) (fields : List (String × Json)) : Json :=
  Json.mkObj (("kind", Json.str kind) :: fields)

def litToJson : LitValue → Json
  | .nat v => obj "nat" [("value", toJson v)]
  | .str v => obj "str" [("value", Json.str v)]
  | .uint8 v => obj "uint8" [("value", toJson v.toNat)]
  | .uint16 v => obj "uint16" [("value", toJson v.toNat)]
  | .uint32 v => obj "uint32" [("value", toJson v.toNat)]
  | .uint64 v => obj "uint64" [("value", toJson v.toNat)]
  | .usize v => obj "usize" [("value", toJson v.toNat)]

def argToJson : Arg pu → Json
  | .erased => obj "erased" []
  | .fvar f => obj "fvar" [("id", fvarToJson f)]
  | .type e _ => obj "type" [("type", typeToJson e)]

def argsToJson (args : Array (Arg pu)) : Json :=
  Json.arr (args.map argToJson)

def paramToJson (p : Param pu) : Json :=
  Json.mkObj [("id", fvarToJson p.fvarId), ("name", nameToJson p.binderName),
    ("type", typeToJson p.type), ("borrow", toJson p.borrow)]

def paramsToJson (ps : Array (Param pu)) : Json := Json.arr (ps.map paramToJson)

def ctorInfoToJson (i : CtorInfo) : Json :=
  Json.mkObj [("name", nameToJson i.name), ("cidx", toJson i.cidx), ("size", toJson i.size),
    ("usize", toJson i.usize), ("ssize", toJson i.ssize)]

def letValueToJson : LetValue pu → Json
  | .lit v => obj "lit" [("lit", litToJson v)]
  | .erased => obj "erased" []
  | .proj t i s _ => obj "proj" [("typeName", nameToJson t), ("idx", toJson i), ("struct", fvarToJson s)]
  | .const n us args _ =>
    obj "const" [("name", nameToJson n), ("levels", Json.arr (us.toArray.map (Json.str ∘ toString))),
      ("args", argsToJson args)]
  | .fvar f args => obj "app" [("fn", fvarToJson f), ("args", argsToJson args)]
  | .ctor i args _ => obj "ctor" [("info", ctorInfoToJson i), ("args", argsToJson args)]
  | .oproj i v _ => obj "oproj" [("idx", toJson i), ("var", fvarToJson v)]
  | .uproj i v _ => obj "uproj" [("idx", toJson i), ("var", fvarToJson v)]
  | .sproj n off v _ => obj "sproj" [("n", toJson n), ("offset", toJson off), ("var", fvarToJson v)]
  | .fap fn args _ => obj "fap" [("name", nameToJson fn), ("args", argsToJson args)]
  | .pap fn args _ => obj "pap" [("name", nameToJson fn), ("args", argsToJson args)]
  | .reset n v _ => obj "reset" [("n", toJson n), ("var", fvarToJson v)]
  | .reuse v i uh args _ =>
    obj "reuse" [("var", fvarToJson v), ("info", ctorInfoToJson i), ("updateHeader", toJson uh),
      ("args", argsToJson args)]
  | .box ty v _ => obj "box" [("type", typeToJson ty), ("var", fvarToJson v)]
  | .unbox v _ => obj "unbox" [("var", fvarToJson v)]
  | .isShared v _ => obj "isShared" [("var", fvarToJson v)]

mutual

partial def codeToJson : Code pu → Json
  | .let d k =>
    obj "let" [("id", fvarToJson d.fvarId), ("name", nameToJson d.binderName),
      ("type", typeToJson d.type), ("value", letValueToJson d.value), ("body", codeToJson k)]
  | .fun d k _ => obj "fun" [("decl", funDeclToJson d), ("body", codeToJson k)]
  | .jp d k => obj "jp" [("decl", funDeclToJson d), ("body", codeToJson k)]
  | .jmp f args => obj "jmp" [("jp", fvarToJson f), ("args", argsToJson args)]
  | .cases c =>
    obj "cases" [("typeName", nameToJson c.typeName), ("resultType", typeToJson c.resultType),
      ("discr", fvarToJson c.discr), ("alts", Json.arr (c.alts.map altToJson))]
  | .return f => obj "return" [("var", fvarToJson f)]
  | .unreach ty => obj "unreach" [("type", typeToJson ty)]
  | .oset f i y k _ =>
    obj "oset" [("var", fvarToJson f), ("idx", toJson i), ("arg", argToJson y), ("body", codeToJson k)]
  | .uset f i y k _ =>
    obj "uset" [("var", fvarToJson f), ("idx", toJson i), ("val", fvarToJson y), ("body", codeToJson k)]
  | .sset f i off y ty k _ =>
    obj "sset" [("var", fvarToJson f), ("idx", toJson i), ("offset", toJson off),
      ("val", fvarToJson y), ("type", typeToJson ty), ("body", codeToJson k)]
  | .setTag f cidx k _ =>
    obj "setTag" [("var", fvarToJson f), ("cidx", toJson cidx), ("body", codeToJson k)]
  | .inc f n check pers k _ =>
    obj "inc" [("var", fvarToJson f), ("n", toJson n), ("check", toJson check),
      ("persistent", toJson pers), ("body", codeToJson k)]
  | .dec f n check pers objs k _ =>
    obj "dec" [("var", fvarToJson f), ("n", toJson n), ("check", toJson check),
      ("persistent", toJson pers), ("objs", toJson objs), ("body", codeToJson k)]
  | .del f k _ => obj "del" [("var", fvarToJson f), ("body", codeToJson k)]

partial def funDeclToJson : FunDecl pu → Json
  | .mk f n ps ty v =>
    Json.mkObj [("id", fvarToJson f), ("name", nameToJson n), ("params", paramsToJson ps),
      ("type", typeToJson ty), ("body", codeToJson v)]

partial def altToJson : Alt pu → Json
  | .alt c ps k _ =>
    obj "alt" [("ctor", nameToJson c), ("params", paramsToJson ps), ("body", codeToJson k)]
  | .ctorAlt i k _ => obj "ctorAlt" [("info", ctorInfoToJson i), ("body", codeToJson k)]
  | .default k => obj "default" [("body", codeToJson k)]

end

def externEntryToJson : ExternEntry → Json
  | .adhoc b => obj "adhoc" [("backend", nameToJson b)]
  | .inline b p => obj "inline" [("backend", nameToJson b), ("pattern", Json.str p)]
  | .standard b f => obj "standard" [("backend", nameToJson b), ("fn", Json.str f)]
  | .opaque => obj "opaque" []

def inlineAttrToJson : Option InlineAttributeKind → Json
  | none => Json.null
  | some .inline => Json.str "inline"
  | some .noinline => Json.str "noinline"
  | some .macroInline => Json.str "macro_inline"
  | some .inlineIfReduce => Json.str "inline_if_reduce"
  | some .alwaysInline => Json.str "always_inline"

def declToJson (d : Decl pu) : Json :=
  let value :=
    match d.value with
    | .code c => obj "code" [("body", codeToJson c)]
    | .extern data => obj "extern" [("entries", Json.arr (data.entries.toArray.map externEntryToJson))]
  Json.mkObj [("name", nameToJson d.name),
    ("levelParams", Json.arr (d.levelParams.toArray.map nameToJson)),
    ("type", typeToJson d.type), ("params", paramsToJson d.params),
    ("recursive", toJson d.recursive), ("safe", toJson d.safe),
    ("inline", inlineAttrToJson d.inlineAttr?), ("value", value)]

end Lean2js.LcnfJson

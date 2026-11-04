import Lean
import Lean2js.LcnfJson

/-!
# Elaborate a Lean file and dump its LCNF as JSON.
-/

namespace Lean2js.LcnfDump

open Lean Lean.Compiler Lean.Compiler.LCNF

/-- Which LCNF phase to dump. See `docs/tickets/lcnf-002-question-phase.md`. -/
inductive DumpPhase where
  | base | mono | impure
  deriving BEq

def DumpPhase.toString : DumpPhase → String
  | .base => "base" | .mono => "mono" | .impure => "impure"

def DumpPhase.parse? : String → Option DumpPhase
  | "base" => some .base
  | "mono" => some .mono
  | "impure" => some .impure
  | _ => none

/-- Default phase. -/
def defaultPhase : DumpPhase := .mono

private def sortedByName (decls : Array (Decl pu)) : Array (Decl pu) :=
  decls.qsort fun a b => a.name.toString < b.name.toString

/-- All declarations of the given phase defined locally in the current module (not imported).
Sorted by name for deterministic output. -/
def localDecls (env : Environment) (phase : DumpPhase) : Array Json :=
  let toJsons {pu : Purity} (ds : Array (Decl pu)) := (sortedByName ds).map LcnfJson.declToJson
  match phase with
  | .base => toJsons ((baseExt.getState env).toArray.map (·.2))
  | .mono => toJsons ((monoExt.getState env).toArray.map (·.2))
  | .impure => toJsons ((impureExt.getState env).toArray.map (·.2))

def dumpJson (env : Environment) (fileName : String) (phase : DumpPhase) : Json :=
  Json.mkObj [("version", toJson LcnfJson.schemaVersion),
    ("leanVersion", Json.str Lean.versionString),
    ("file", Json.str fileName),
    ("phase", Json.str phase.toString),
    ("decls", Json.arr (localDecls env phase))]

/-! ## Dependency closure (`--with-deps`) -/

/-- Constants and type names referenced by code. -/
structure Refs where
  consts : NameSet := {}
  types : NameSet := {}

private def addConst (n : Name) : StateM Refs Unit := modify fun r => { r with consts := r.consts.insert n }
private def addType (n : Name) : StateM Refs Unit := modify fun r => { r with types := r.types.insert n }

def letValueRefs : LetValue pu → StateM Refs Unit
  | .const n .. | .fap n .. | .pap n .. => addConst n
  | .proj t .. => addType t
  | .ctor i .. | .reuse _ i .. => addConst i.name
  | _ => pure ()

mutual
partial def codeRefs : Code pu → StateM Refs Unit
  | .let d k => do letValueRefs d.value; codeRefs k
  | .fun d k _ | .jp d k => do codeRefs d.value; codeRefs k
  | .cases c => do
    addType c.typeName
    for a in c.alts do altRefs a
  | .jmp .. | .return .. | .unreach .. => pure ()
  | .oset _ _ _ k _ | .uset _ _ _ k _ | .sset _ _ _ _ _ k _ | .setTag _ _ k _
  | .inc _ _ _ _ k _ | .dec _ _ _ _ _ k _ | .del _ k _ => codeRefs k

partial def altRefs : Alt pu → StateM Refs Unit
  | .alt _ _ k _ | .ctorAlt _ k _ | .default k => codeRefs k
end

def declRefs (d : Decl pu) : Refs :=
  match d.value with
  | .code c => ((codeRefs c).run {}).2
  | .extern _ => {}

/-- Module a declaration comes from (`null` for the current file). -/
def moduleOf (env : Environment) (n : Name) : Json :=
  match env.getModuleIdxFor? n with
  | some idx => Json.str env.header.moduleNames[idx.toNat]!.toString
  | none => Json.null

def inductiveToJson (v : InductiveVal) (env : Environment) : Json :=
  let ctors := v.ctors.toArray.filterMap fun c =>
    match env.find? c with
    | some (.ctorInfo cv) =>
      some (Json.mkObj [("name", LcnfJson.nameToJson c), ("cidx", toJson cv.cidx),
        ("numParams", toJson cv.numParams), ("numFields", toJson cv.numFields)])
    | _ => none
  Json.mkObj [("name", LcnfJson.nameToJson v.name), ("numParams", toJson v.numParams),
    ("numIndices", toJson v.numIndices), ("isRec", toJson v.isRec), ("ctors", Json.arr ctors)]

/-- Dump the `mono` declarations of the file plus all declarations transitively reachable from
them (including imported ones), constructor metadata of every inductive type used, and the list
of referenced names for which no LCNF exists (`missing`: constructors excluded). -/
def dumpWithDepsJson (env : Environment) (fileName : String) : Json := Id.run do
  let roots := (monoExt.getState env).toArray.map (·.1)
  let mut work : Array Name := roots
  let mut seen : NameSet := {}
  let mut decls : Array (Decl .pure) := #[]
  let mut types : NameSet := {}
  let mut missing : NameSet := {}
  while work.size > 0 do
    let n := work.back!
    work := work.pop
    if seen.contains n then continue
    seen := seen.insert n
    match getDeclCore? env monoExt n with
    | some d =>
      decls := decls.push d
      let r := declRefs d
      for t in r.types.toList do types := types.insert t
      for c in r.consts.toList do
        unless seen.contains c do work := work.push c
    | none =>
      match env.find? n with
      | some (.ctorInfo cv) => types := types.insert cv.induct
      | _ => missing := missing.insert n
  let sorted := sortedByName decls
  let declJsons := sorted.map fun d =>
    match LcnfJson.declToJson d with
    | .obj kvs => Json.obj (kvs.insert "module" (moduleOf env d.name))
    | j => j
  let inds := types.toList.toArray.qsort (fun a b => a.toString < b.toString) |>.filterMap fun t =>
    match env.find? t with
    | some (.inductInfo v) => some (inductiveToJson v env)
    | _ => none
  Json.mkObj [("version", toJson LcnfJson.schemaVersion),
    ("leanVersion", Json.str Lean.versionString),
    ("file", Json.str fileName),
    ("phase", Json.str "mono"),
    ("withDeps", toJson true),
    ("decls", Json.arr declJsons),
    ("inductives", Json.arr inds),
    ("missing", Json.arr (missing.toList.toArray.qsort (fun a b => a.toString < b.toString) |>.map LcnfJson.nameToJson))]

/-- Elaborate `fileName`; compiler/elaboration messages go to stderr. Returns `none` on errors. -/
unsafe def elaborateUnsafe (fileName : String) : IO (Option Environment) := do
  let input ← IO.FS.readFile fileName
  initSearchPath (← findSysroot)
  enableInitializersExecution
  let (out, env?) ← IO.FS.withIsolatedStreams (isolateStderr := false) do
    Elab.runFrontend input {} fileName `_lcnfdump
  IO.eprint out
  return env?

@[implemented_by elaborateUnsafe]
opaque elaborate (fileName : String) : IO (Option Environment)

end Lean2js.LcnfDump

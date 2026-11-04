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

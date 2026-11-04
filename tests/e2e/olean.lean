import Lean
open Lean

/-- Reads real .olean files (sysroot from $LEAN_SYSROOT) and prints a digest of their contents. -/
def digest (mod : String) : IO Unit := do
  let sysroot ← IO.getEnv "LEAN_SYSROOT"
  let fname : System.FilePath := (sysroot.getD ".") / "lib" / "lean" / (mod ++ ".olean")
  let (data, _) ← readModuleData fname
  let mut h : UInt64 := 7
  let mut kinds : Array Nat := Array.replicate 8 0
  for c in data.constants do
    let cv := c.toConstantVal
    h := mixHash h (hash cv.name)
    h := mixHash h (hash cv.type)
    h := mixHash h (hash cv.levelParams)
    let k := match c with
      | .axiomInfo _ => 0 | .defnInfo _ => 1 | .thmInfo _ => 2 | .opaqueInfo _ => 3
      | .quotInfo _ => 4 | .inductInfo _ => 5 | .ctorInfo _ => 6 | .recInfo _ => 7
    kinds := kinds.modify k (· + 1)
    match c with
    | .defnInfo d => h := mixHash h (hash d.value)
    | .ctorInfo d => h := mixHash h (d.cidx.toUInt64 + d.numFields.toUInt64 * 31 + d.numParams.toUInt64 * 17)
    | .inductInfo d => h := mixHash h (d.numParams.toUInt64 + d.numIndices.toUInt64 * 31 + (if d.isRec then 1 else 0))
    | _ => pure ()
  IO.println s!"{mod}: imports={data.imports.map (·.module)} consts={data.constNames.size} extra={data.extraConstNames.size} kinds={kinds} hash={h}"
  let names := data.entries.map fun (n, es) => s!"{n}:{es.size}"
  IO.println s!"  entries {names.size}: {names.toList.take 6}"

def main : IO Unit := do
  digest "Init/Prelude"
  digest "Init/Core"
  digest "Init/Data/Nat/Basic"
  digest "Init/Data/Range/Polymorphic/UInt"
  digest "Init/Data/String/Basic"
  digest "Lean/Expr"

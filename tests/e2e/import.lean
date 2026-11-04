import Lean
open Lean

/-- `importModules` in JS: reads the real Init .olean files and builds an Environment. -/
def main : IO Unit := do
  let sysroot ← IO.getEnv "LEAN_SYSROOT"
  searchPathRef.set [(sysroot.getD ".") / "lib" / "lean"]
  let env ← importModules #[{ module := `Init }] {}
  IO.println s!"modules: {env.header.moduleNames.size}"
  IO.println s!"constants: {env.constants.map₁.size}"
  match env.find? `Nat.add_comm with
  | some ci => IO.println s!"Nat.add_comm : {repr ci.type}"
  | none => IO.println "Nat.add_comm missing"
  match env.find? `List.map with
  | some (.defnInfo d) => IO.println s!"List.map safety={repr d.safety} nlevels={d.levelParams}"
  | _ => IO.println "List.map missing"
  IO.println s!"{(env.find? `Nat).isSome} {(env.find? `Nat.rec).isSome} {env.contains `Nat.succ}"
  IO.println s!"{isClass env `Monad} {isStructure env `Prod} {(getStructureFields env `Prod)}"

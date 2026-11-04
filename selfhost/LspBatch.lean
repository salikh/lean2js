import Lean
import Lean2js.Kernel
import Lean2js.CodegenIR
open Lean

/-- The actual Lean file worker (`Lean.Server.FileWorker`) on in-memory LSP messages: reads framed JSON-RPC messages from stdin until `exit`, writes the worker's output to stdout (demo-002 experiment). -/
unsafe def main : IO UInt32 := do
  enableInitializersExecution
  let sysroot ← IO.getEnv "LEAN_SYSROOT"
  searchPathRef.set [(sysroot.getD ".") / "lib" / "lean"]
  Lean.Server.FileWorker.initAndRunWorker (← IO.getStdin) (← IO.getStdout) (← IO.getStderr) {}
  return 0

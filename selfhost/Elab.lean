import Lean
import Lean2js.Kernel
import Lean2js.CodegenIR
import Lean2js.Session   -- its `lean2js_session_*` exports are used by the interactive web demo (web/selfhost/demo.html)
open Lean Elab

/-!
Self-hosted elaborator (ticket self-009): reads Lean source from stdin, elaborates it with the *Lean frontend running as JavaScript*
(transpiled by lean2js with `--init-all`), and prints the messages. The standard library is loaded from the `.olean` files under
`$LEAN_SYSROOT/lib/lean`.
-/
unsafe def main : IO UInt32 := do
  enableInitializersExecution
  let sysroot ← IO.getEnv "LEAN_SYSROOT"
  searchPathRef.set [(sysroot.getD ".") / "lib" / "lean"]
  let input ← (← IO.getStdin).readToEnd
  let inputCtx := Parser.mkInputContext input "<input>"
  let (header, parserState, messages) ← Parser.parseHeader inputCtx
  let (env, messages) ← processHeader header {} messages inputCtx
  for msg in messages.toList do IO.print (← msg.toString (includeEndPos := false))   -- import errors
  let env := env.setMainModule `Main
  let s ← IO.processCommands inputCtx parserState (Command.mkState env messages {})
  let mut ok := true
  for msg in s.commandState.messages.toList do
    IO.print (← msg.toString (includeEndPos := false))
    if msg.severity == .error then ok := false
  return if ok then 0 else 1

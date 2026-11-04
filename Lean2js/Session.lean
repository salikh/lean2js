import Lean
import Lean2js.Kernel
import Lean2js.CodegenIR
open Lean Elab

/-!
Session API of the self-hosted Lean frontend (ticket demo-001): a long-lived elaboration state that survives between inputs, for the
interactive web demo and tests. Exported under `lean2js_session_*`; call from JavaScript through `rt.exports` (IO functions take the state
token as last argument and return an `EStateM` result).
-/

/-- Elaboration state kept between inputs. -/
structure Session where
  cmdState : Command.State

/-- Imports `Init` (the library is found under `$LEAN_SYSROOT/lib/lean`) and starts an empty session. -/
@[export lean2js_session_new]
unsafe def Session.new (_unit : Unit) : IO Session := do
  enableInitializersExecution
  let sysroot ← IO.getEnv "LEAN_SYSROOT"
  searchPathRef.set [(sysroot.getD ".") / "lib" / "lean"]
  let inputCtx := Parser.mkInputContext "" "<init>"
  let (header, _, messages) ← Parser.parseHeader inputCtx
  let (env, messages) ← processHeader header {} messages inputCtx
  let env := env.setMainModule `Main
  if messages.hasErrors then
    throw <| IO.userError (← messages.toList.foldlM (fun acc m => return acc ++ (← m.toString)) "")
  return { cmdState := Command.mkState env {} {} }

/-- Elaborates `input` (any number of commands) in the session; returns the new session and the rendered messages. -/
@[export lean2js_session_run]
def Session.run (s : Session) (input : String) (fileName : String) : IO (Session × String) := do
  let inputCtx := Parser.mkInputContext input fileName
  let st ← IO.processCommands inputCtx {} { s.cmdState with messages := {} }
  let mut out := ""
  for msg in st.commandState.messages.toList do
    out := out ++ (← msg.toString (includeEndPos := false))
  return ({ cmdState := { st.commandState with messages := {} } }, out)

/-- Console input: a command is run as is, anything else is evaluated with `#eval` (so `main`, `1 + 2` and `IO.println "x"` work). -/
@[export lean2js_session_console]
def Session.console (s : Session) (line : String) : IO (Session × String) := do
  let env := s.cmdState.env
  let isCommand := match Parser.runParserCategory env `command line "<console>" with | .ok _ => true | .error _ => false
  let input := if isCommand then line else "#eval " ++ line
  s.run input "<console>"

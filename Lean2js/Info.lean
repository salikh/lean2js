import Lean
import Lean2js.Session
open Lean Elab Meta

/-!
Infoview-style queries on top of the elaborator (tickets info-001 … info-006): the proof goals, the expected type of a term and the messages
at a position of a source text. "Prefix mode" (`infoAtEnd`) asks for the end of the text: emulates writing a proof, the text so far may end
in the middle of a tactic block (Lean's error recovery elaborates it with `sorry`). "Cursor mode" (`infoAt`) asks for an LSP position
(line, UTF-16 character) inside a complete text. The goal selection rules are those of the language server (`InfoTree.goalsAt?`,
`termGoalAt?`); the text is rendered like `$/lean/plainGoal` / `$/lean/plainTermGoal`.
-/

namespace Lean2js.Info

/-- Rendered goals of `GoalsAtResult`s, as the server's `handlePlainGoal` does. -/
private def renderGoals (rs : List GoalsAtResult) : IO (Array String) := do
  let mut all : Array String := #[]
  for { ctxInfo := ci, tacticInfo := ti, useAfter := useAfter, .. } in rs do
    let ciAfter := { ci with mctx := ti.mctxAfter }
    let ci := if useAfter then ciAfter else { ci with mctx := ti.mctxBefore }
    let goals ← ci.runMetaM {} (do
      let goals := List.toArray <| if useAfter then ti.goalsAfter else ti.goalsBefore
      goals.mapM Widget.goalToInteractive)
    all := all ++ goals.map (toString ·.pretty)
  return all

private def rangeJson (text : FileMap) (r : Lsp.Range) : Json := Json.mkObj
  [("start", Json.mkObj [("line", r.start.line), ("character", r.start.character)]),
   ("end", Json.mkObj [("line", r.end.line), ("character", r.end.character)])]

private def severityName : MessageSeverity → String
  | .information => "information" | .warning => "warning" | .error => "error"

/-- The info at byte position `pos` of `source` (elaborated in the session's environment; the session is not modified). -/
def infoAtPos (s : Session) (source : String) (pos : String.Pos.Raw) : IO Json := do
  let inputCtx := Parser.mkInputContext source "<info>"
  let text := inputCtx.fileMap
  let st ← IO.processCommands inputCtx {} { s.cmdState with messages := {} }
  let trees := st.commandState.infoState.trees.toList
  -- goals
  let mut goalRes : List GoalsAtResult := []
  for t in trees do
    let rs := t.goalsAt? text pos
    unless rs.isEmpty do
      goalRes := rs
      break
  let goals ← renderGoals goalRes
  let rendered :=
    if goalRes.isEmpty then "" else if goals.isEmpty then "no goals"
    else String.intercalate "\n---\n" (goals.toList.map fun g => s!"```lean\n{g}\n```")
  -- term goal
  let mut termGoal : Json := Json.null
  for t in trees do
    if let some { ctx := ci, info := i@(Info.ofTermInfo ti), .. } := t.termGoalAt? pos then
      let ty ← ci.runMetaM i.lctx do
        instantiateMVars <| ti.expectedType?.getD (← Meta.inferType ti.expr)
      let lctx' := if ti.isBinder then i.lctx.pop else i.lctx
      let goal ← ci.runMetaM lctx' do
        Widget.goalToInteractive (← Meta.mkFreshExprMVar ty).mvarId!
      let range := match i.range? with
        | some r => rangeJson text (r.toLspRange text)
        | none => Json.null
      termGoal := Json.mkObj [("goal", toString goal.pretty), ("range", range)]
      break
  -- messages: all of them, flagged when their range contains the position
  let mut msgs : Array Json := #[]
  for m in st.commandState.messages.toList do
    let startPos := text.ofPosition m.pos
    let endPos := (m.endPos.map text.ofPosition).getD startPos
    let contains := startPos ≤ pos && pos ≤ endPos
    let range := rangeJson text ⟨text.leanPosToLspPos m.pos, text.leanPosToLspPos (m.endPos.getD m.pos)⟩
    msgs := msgs.push <| Json.mkObj
      [("range", range), ("severity", severityName m.severity), ("text", (← m.data.toString)), ("atCursor", contains)]
  let lsp := text.leanPosToLspPos (text.toPosition pos)
  return Json.mkObj
    [("position", Json.mkObj [("line", lsp.line), ("character", lsp.character)]),
     ("goals", toJson goals), ("rendered", rendered), ("termGoal", termGoal), ("messages", Json.arr msgs)]

/-- Cursor mode: the info at the LSP position (`line`, UTF-16 `character`) of `source`, as pretty-printed JSON. -/
@[export lean2js_session_info]
def infoAt (s : Session) (source : String) (line character : Nat) : IO String := do
  let text := (Parser.mkInputContext source "<info>").fileMap
  let pos := text.lspPosToUtf8Pos ⟨line, character⟩
  return (← infoAtPos s source pos).pretty

/-- Prefix mode: the info at the end of `source` (the text written so far). -/
@[export lean2js_session_info_end]
def infoAtEnd (s : Session) (source : String) : IO String := do
  return (← infoAtPos s source source.rawEndPos).pretty

end Lean2js.Info

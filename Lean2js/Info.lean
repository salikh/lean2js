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

open Language in
/-- The first command snapshot whose range (with trailing whitespace) contains `hoverPos` (cf. `Lean.Language.Lean.findCmdParsedSnap`). -/
private partial def findCmd (first : Lean.Language.Lean.CommandParsedSnapshot) (text : FileMap) (hoverPos : String.Pos.Raw) :
    Option Lean.Language.Lean.CommandParsedSnapshot :=
  let contains (c : Lean.Language.Lean.CommandParsedSnapshot) : Bool :=
    match c.stx.getRangeWithTrailing? (canonicalOnly := true) with
    | some range => text.rangeContainsHoverPos range hoverPos (includeStop := false)
    | none => false
  let isAfter (c : Lean.Language.Lean.CommandParsedSnapshot) : Bool :=
    match c.stx.getPos? (canonicalOnly := true) with
    | some startPos => hoverPos < startPos
    | none => false
  let rec go (c : Lean.Language.Lean.CommandParsedSnapshot) : Option Lean.Language.Lean.CommandParsedSnapshot :=
    if contains c then some c
    else if isAfter c then none
    else match c.nextCmdSnap? with
      | some next => go next.task.get
      | none => none
  go first

open Language in
/-- The goals at `hoverPos`: the language server's `findGoalsAt?` (Lean/Server/FileWorker/RequestHandling.lean) on the snapshot tree of the command. -/
private def findGoalsAt (cmdParsed : Lean.Language.Lean.CommandParsedSnapshot) (text : FileMap) (hoverPos : String.Pos.Raw) :
    List GoalsAtResult :=
  let getPositions (stx : Syntax) : Option (String.Pos.Raw × String.Pos.Raw × String.Pos.Raw) := do
    let pos ← stx.getPos? (canonicalOnly := true)
    let tailPos ← stx.getTailPos? (canonicalOnly := true)
    let trailingPos? ← stx.getTrailingTailPos? (canonicalOnly := true)
    return (pos, tailPos, trailingPos?)
  let t := toSnapshotTree cmdParsed.elabSnap |>.foldSnaps [] fun snap oldGoals => Id.run do
    let some stx := snap.stx?
      | return .pure (oldGoals, .proceed (foldChildren := false))
    let some (pos, tailPos, trailingPos) := getPositions stx
      | return .pure (oldGoals, .proceed (foldChildren := true))
    let snapRange : Lean.Syntax.Range := ⟨pos, trailingPos⟩
    let hasNoTrailingWhitespace := tailPos == trailingPos
    if ! text.rangeContainsHoverPos snapRange hoverPos (includeStop := hasNoTrailingWhitespace) then
      return .pure (oldGoals, .proceed (foldChildren := false))
    return snap.task.map (sync := true) fun tree => Id.run do
      let some infoTree := tree.element.infoTree?
        | return (oldGoals, .proceed (foldChildren := true))
      let goals := infoTree.goalsAt? text hoverPos
      let optimalSnapRange : Lean.Syntax.Range := ⟨pos, tailPos⟩
      let isOptimalGoalSet :=
        text.rangeContainsHoverPos optimalSnapRange hoverPos (includeStop := hasNoTrailingWhitespace)
          || goals.any fun goal => ! goal.indented
      if isOptimalGoalSet then
        return (goals, .done)
      return (goals, .proceed (foldChildren := true))
  t.get

open Language in
/-- The term goal at `hoverPos` (the language server's `getInteractiveTermGoal` lookup). -/
private def findTermGoalTree (cmdParsed : Lean.Language.Lean.CommandParsedSnapshot) (text : FileMap) (hoverPos : String.Pos.Raw) :
    Option Elab.InfoTree :=
  match (toSnapshotTree cmdParsed.elabSnap |>.findInfoTreeAtPos text hoverPos (includeStop := true)).get with
  | some t => some t
  | none => cmdParsed.elabSnap.infoTreeSnap.task.get.infoTree?

/-- The info at byte position `pos` of `source` (elaborated in the session's environment; the session is not modified). -/
def infoAtPos (s : Session) (source : String) (pos : String.Pos.Raw) : IO Json := do
  let inputCtx := Parser.mkInputContext source "<info>"
  let text := inputCtx.fileMap
  let inc ← IO.processCommandsIncrementally inputCtx {} { s.cmdState with messages := {} } none
  let st := inc.toState
  let cmd? := findCmd inc.initialSnap text pos
  -- goals
  let goalRes := match cmd? with | some c => findGoalsAt c text pos | none => []
  let goals ← renderGoals goalRes
  let rendered :=
    if goalRes.isEmpty then "" else if goals.isEmpty then "no goals"
    else String.intercalate "\n---\n" (goals.toList.map fun g => s!"```lean\n{g}\n```")
  -- term goal
  let mut termGoal : Json := Json.null
  if let some c := cmd? then
    if let some t := findTermGoalTree c text pos then
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

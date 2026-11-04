import Lean
import Lean2js.Info
open Lean

/-- Runs the cases of tests/info/cases.json through `Lean2js.Info` and prints `[{name, goal, termGoal}]` in the shape of the language server's
`$/lean/plainGoal` / `$/lean/plainTermGoal` responses (compared with the real server by tests/info/compare.mjs). -/
unsafe def main : IO Unit := do
  let cases ← IO.ofExcept (Json.parse (← IO.FS.readFile "tests/info/cases.json"))
  let s ← Session.new ()
  let mut out : Array Json := #[]
  for c in cases.getArr? |>.toOption |>.getD #[] do
    let source := c.getObjValAs? String "source" |>.toOption |>.getD ""
    let line := c.getObjValAs? Nat "line" |>.toOption |>.getD 0
    let ch := c.getObjValAs? Nat "character" |>.toOption |>.getD 0
    let r ← IO.ofExcept (Json.parse (← Lean2js.Info.infoAt s source line ch))
    let rendered := r.getObjValAs? String "rendered" |>.toOption |>.getD ""
    let goal := if rendered == "" then Json.null else Json.mkObj [("goals", r.getObjValD "goals"), ("rendered", rendered)]
    out := out.push <| Json.mkObj [("name", c.getObjValD "name"), ("goal", goal), ("termGoal", r.getObjValD "termGoal"), ("hover", r.getObjValD "hover")]
  IO.println (Json.arr out).compress

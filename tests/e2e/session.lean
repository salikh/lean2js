import Lean
import Lean2js.Session
open Lean

/-- The session API used by the interactive demo (demo-001): script, console lines (commands and `#eval`ed terms/IO actions), changing the data file between runs. -/
unsafe def main : IO Unit := do
  IO.FS.writeFile "data.json" (← IO.FS.readFile "web/selfhost/examples/stats.json")
  let script ← IO.FS.readFile "web/selfhost/examples/stats.lean"
  let s ← Session.new ()
  let (s, out) ← s.run script "<script>"
  IO.println s!"[script] {out}"
  let mut s := s
  for line in ["main", "mean #[1.0, 2.0, 6.0]", "def double (x : Nat) := 2 * x", "double 21", "IO.println \"hello from the console\"",
      "(← IO.FS.readFile \"data.json\").length", "#check @double", "nosuchname", "stdev #[2.0, 4.0, 4.0, 4.0, 5.0, 5.0, 7.0, 9.0]"] do
    let (s', out) ← s.console line
    s := s'
    IO.println s!"> {line}\n{out}"
  IO.FS.writeFile "data.json" "[10, 20]"
  let (s', out) ← s.console "main"
  s := s'
  IO.println s!"> main (new data)\n{out}"
  IO.FS.removeFile "data.json"

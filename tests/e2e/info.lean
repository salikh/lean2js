import Lean
import Lean2js.Info
open Lean

/-- Infoview queries (info-004): prefix mode (proof written so far) and cursor mode, natively vs. JS. -/
unsafe def main : IO Unit := do
  let s ← Session.new ()
  let proof := "theorem t (p q : Prop) (hp : p) (hq : q) : p ∧ q := by\n  constructor\n  "
  IO.println (← Lean2js.Info.infoAtEnd s proof)
  let full := "theorem t (p q : Prop) (hp : p) (hq : q) : p ∧ q := by\n  constructor\n  · exact hp\n  · exact hq\n\n#check t\ndef f (n : Nat) : Nat := n + 1\n"
  IO.println (← Lean2js.Info.infoAt s full 2 4)      -- after `constructor`
  IO.println (← Lean2js.Info.infoAt s full 3 10)     -- inside `exact hp`
  IO.println (← Lean2js.Info.infoAt s full 5 7)      -- `#check t` message
  IO.println (← Lean2js.Info.infoAt s full 6 28)     -- term `n + 1` in a def

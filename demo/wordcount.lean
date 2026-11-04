import Std.Data.HashMap
open Std

def main : IO Unit := do
  let text := "the cat and the dog and the bird"
  let counts := text.splitOn " " |>.foldl (fun (m : HashMap String Nat) w => m.insert w (m.getD w 0 + 1)) {}
  for (w, n) in counts.toList.toArray.qsort (fun a b => a.1 < b.1) do
    IO.println s!"{w}: {n}"

import Std.Data.HashMap
open Std

def main : IO Unit := do
  let mut m : HashMap String Nat := {}
  for (k, v) in [("one", 1), ("two", 2), ("three", 3), ("four", 4)] do
    m := m.insert k v
  IO.println (m.size)
  IO.println (m.get? "two")
  IO.println (m.getD "zzz" 0)
  IO.println (m.contains "four")
  let m2 := m.erase "one"
  IO.println (m2.toList.map (·.1) |>.mergeSort)
  let mut n : HashMap Nat Nat := {}
  for i in [0:1000] do
    n := n.insert i (i * i)
  IO.println (n.size)
  IO.println (n.get! 999)
  IO.println (n.fold (fun acc _ v => acc + v) 0)
  -- iteration order must match native Lean
  IO.println (m2.toList)
  IO.println (n.toList.take 5)

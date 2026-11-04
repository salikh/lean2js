import Std.Data.HashMap

def main : IO Unit := do
  let mut arr : Array Nat := #[]
  for i in [0:1000000] do
    arr := arr.push (i * 7 % 1000)
  IO.println arr.size
  let mut m : Std.HashMap Nat Nat := {}
  for i in [0:200000] do
    m := m.insert i (i * i)
  IO.println m.size
  IO.println (m.getD 199999 0)
  let sorted := (arr.extract 0 100000).qsort (· < ·)
  IO.println (sorted[0]!, sorted[99999]!)
  let mut s := 0
  for x in arr do s := s + x
  IO.println s
  let mut cnt := 0
  for i in [0:3000000] do
    if i % 7 == 0 then cnt := cnt + 1
  IO.println cnt

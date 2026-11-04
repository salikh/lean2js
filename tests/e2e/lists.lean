def main : IO Unit := do
  let xs := List.range 10
  IO.println xs
  IO.println (xs.map (· * 2))
  IO.println (xs.filter (· % 2 == 0))
  IO.println (xs.foldl (· + ·) 0)
  IO.println (xs.reverse)
  IO.println (xs.length)
  IO.println ([3,1,2].mergeSort)
  IO.println (xs.zip (xs.map (· + 1)))
  IO.println ((xs.head?), ([] : List Nat).head?)

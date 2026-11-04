def main : IO Unit := do
  let mut a : Array Nat := #[]
  for i in [0:10] do
    a := a.push (i * i)
  IO.println a
  IO.println a.size
  IO.println (a.map (· + 1))
  IO.println (a.foldl (· + ·) 0)
  IO.println (a[3]!)
  IO.println (a.set! 3 100)
  IO.println (a.reverse)
  IO.println (a.toList.take 3)
  IO.println ((a.qsort (· > ·)).toList)

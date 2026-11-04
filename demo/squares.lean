def main : IO Unit := do
  let xs := List.range 10
  let sq := xs.map (fun x => x * x)
  IO.println s!"squares: {sq}"
  IO.println s!"sum: {sq.foldl (· + ·) 0}"

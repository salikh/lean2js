def main : IO Unit := do
  let r ← IO.mkRef 0
  for i in [1:11] do
    r.modify (· + i)
  IO.println (← r.get)
  try
    throw (IO.userError "boom")
  catch e =>
    IO.println s!"caught: {e}"
  IO.eprintln "to stderr"
  let x ← pure 42
  IO.println s!"x = {x}"

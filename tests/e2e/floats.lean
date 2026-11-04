def main : IO Unit := do
  let x : Float := 3.14159
  IO.println x
  IO.println (x * 2.0)
  IO.println (Float.sqrt 2.0)
  IO.println (Float.floor 2.7)
  IO.println (x.toString)
  IO.println ((10 : Float) / 3)
  IO.println (Float.ofNat 5)
  IO.println ((2.5 : Float).toUInt64)
  IO.println (1.0 / 0.0 : Float)
  IO.println (Float.ofScientific 12345 true 2)

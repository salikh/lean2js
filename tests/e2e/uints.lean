def main : IO Unit := do
  let a : UInt8 := 250
  IO.println (a + 10)
  let b : UInt32 := 4000000000
  IO.println (b + b)
  let c : UInt64 := 0xFFFFFFFFFFFFFFFF
  IO.println (c + 2)
  IO.println ((5 : UInt64) * 3)
  IO.println ((1 : UInt32) <<< 31)
  IO.println ((255 : UInt8).toNat)
  IO.println ((300 : Nat).toUInt8)
  IO.println (Char.ofNat 955)

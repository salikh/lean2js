/-- Fixed-width signed integers, Float32, exact division, powMod, misc runtime queries. -/
def main : IO Unit := do
  let a : Int8 := -100
  let b : Int8 := 77
  IO.println s!"{a + b} {a - b} {a * b} {a / b} {a % b} {-a} {decide (a < b)} {decide (a ≤ b)} {a == b} {a >>> 2} {a <<< 1} {a &&& b} {a ||| b} {a ^^^ b} {~~~a}"
  IO.println s!"{(Int8.ofInt 200)} {(Int8.ofNat 300)} {a.toInt} {a.toInt16} {a.toInt32} {a.toInt64} {(-128 : Int8) / (-1 : Int8)} {(5 : Int8) / 0} {(5 : Int8) % 0}"
  let c : Int16 := -30000
  let d : Int16 := 12345
  IO.println s!"{c + d} {c * d} {c / d} {c % d} {c.toInt8} {c.toInt32} {d <<< 3} {c >>> 3}"
  let e : Int32 := -2000000000
  let f : Int32 := 1234567890
  IO.println s!"{e + f} {e - f} {e * f} {e / f} {e % f} {e.toInt16} {e.toInt64} {e >>> 7} {e <<< 33}"
  let g : Int64 := -9000000000000000000
  let h : Int64 := 5000000000000000000
  IO.println s!"{g + h} {g - h} {g * h} {g / h} {g % h} {g.toInt32} {g.toInt} {g >>> 5} {decide (g < h)} {(Int64.ofInt (-3)).toInt} {h.toInt8}"
  let i : ISize := -17
  IO.println s!"{i * 3} {i / 4} {i % 4} {i.toInt}"
  let x : Float32 := 1.1
  let y : Float32 := 3.3
  IO.println s!"{x + y} {x * y} {x / y} {x - y} {-x} {decide (x < y)} {x.toFloat} {(2.5 : Float).toFloat32} {x.toBits} {Float32.ofBits 0x40490fdb}"
  IO.println s!"{Nat.pow 7 100 % 1000000007} {(Nat.pow 2 200).log2} {Nat.gcd 462 1071}"

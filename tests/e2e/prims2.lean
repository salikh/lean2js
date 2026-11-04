def main : IO Unit := do
  let p ← IO.Promise.new (α := Nat)
  let t := p.result?
  p.resolve 42
  IO.println (t.get)
  let a : Int64 := -5
  IO.println (a.toInt, (a * 3).toInt, decide (a < 2), (Int64.ofNat 7).toInt)
  IO.println ((2.0 : Float).isNaN, (1.0/0.0 : Float).isInf)
  IO.println ((String.Pos.Raw.mk 1).isValid "aé", (String.Pos.Raw.mk 2).isValid "aé", (String.Pos.Raw.mk 3).isValid "aé", (String.Pos.Raw.mk 4).isValid "aé")

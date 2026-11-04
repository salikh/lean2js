def main : IO Unit := do
  let b := "héllo".toUTF8
  IO.println b.size
  IO.println b.toList
  let b2 := b.push 33
  IO.println b2.size
  IO.println (String.fromUTF8! b2)
  IO.println (b2.get! 1)
  let mut ba := ByteArray.empty
  for i in [0:5] do ba := ba.push i.toUInt8
  IO.println ba.data
  IO.println (ba.extract 1 3).toList
  let fa := FloatArray.empty.push 1.5 |>.push 2.5
  IO.println fa.size

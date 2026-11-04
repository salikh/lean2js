/-- ByteArray.push in a loop (amortized O(1)), sharing (copy on write after push), FloatArray. -/
def main : IO Unit := do
  let mut b : ByteArray := .empty
  for i in [0:300000] do b := b.push (i % 251).toUInt8
  IO.println s!"{b.size} {b[0]!} {b[1000]!} {b[299999]!}"
  let c := b                      -- shared
  let d := c.push 7
  IO.println s!"{c.size} {d.size} {d[300000]!}"
  let e := c.set! 5 99
  IO.println s!"{c[5]!} {e[5]!}"
  let mut f : FloatArray := .empty
  for i in [0:1000] do f := f.push i.toFloat
  IO.println s!"{f.size} {f[999]!}"

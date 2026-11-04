def main : IO UInt32 := do
  let t0 ← IO.monoMsNow
  let n0 ← IO.monoNanosNow
  let sum := (List.range 1000).foldl (· + ·) 0
  let t1 ← IO.monoMsNow
  let n1 ← IO.monoNanosNow
  IO.println s!"sum {sum} monotonic {decide (t1 >= t0)} {decide (n1 >= n0)}"
  let home ← IO.getEnv "LEAN2JS_SURELY_UNSET_VARIABLE"
  IO.println home
  IO.eprintln "exiting"
  IO.Process.exit 7

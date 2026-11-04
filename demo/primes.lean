def main : IO Unit := do
  let n := 50
  let mut isPrime := Array.replicate (n + 1) true
  for i in [2:n+1] do
    let mut j := i * i
    while isPrime[i]! && j ≤ n do
      isPrime := isPrime.set! j false
      j := j + i
  IO.println s!"primes up to {n}: {(List.range (n + 1)).filter fun i => i ≥ 2 && isPrime[i]!}"

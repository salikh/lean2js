def step : StateT Nat IO Unit := do
  let n ← get
  IO.println s!"n = {n}"
  set (n * 2 + 1)

def readerTest : ReaderT String IO Unit := do
  let env ← read
  IO.println s!"env = {env}"

def exceptTest (n : Nat) : ExceptT String IO Nat := do
  if n == 0 then throw "zero!"
  IO.println "ok"
  return n + 1

def main : IO Unit := do
  let ((), s) ← (do step; step; step).run 1
  IO.println s
  readerTest.run "hello"
  let r ← (exceptTest 0).run
  IO.println (repr r)
  let r ← (exceptTest 5).run
  IO.println (repr r)
  let mut acc := #[]
  for i in [0:3] do
    for j in [0:3] do
      if i == j then continue
      acc := acc.push (i, j)
  IO.println acc
  let rec fib : Nat → Nat
    | 0 => 0 | 1 => 1 | n+2 => fib n + fib (n+1)
  IO.println (fib 20)

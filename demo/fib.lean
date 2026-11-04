def fib (n : Nat) : Nat := Id.run do
  let mut (a, b) := (0, 1)
  for _ in [0:n] do
    (a, b) := (b, a + b)
  return a

def main : IO Unit :=
  IO.println s!"fib 200 = {fib 200}"

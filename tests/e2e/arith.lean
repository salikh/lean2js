def fact : Nat → Nat
  | 0 => 1
  | n+1 => (n+1) * fact n

def fib (n : Nat) : Nat := Id.run do
  let mut a := 0
  let mut b := 1
  for _ in [0:n] do
    (a, b) := (b, a + b)
  return a

def main : IO Unit := do
  IO.println (fact 25)
  IO.println (fib 100)
  IO.println (10 - 20)
  IO.println ((7 : Int) - 20)
  IO.println ((-7 : Int) / 2)
  IO.println ((-7 : Int) % 3)
  IO.println (2 ^ 100)
  IO.println (100 / 7)
  IO.println (100 % 7)
  IO.println (Nat.gcd 48 18)
  IO.println (decide (3 < 5) : Bool)

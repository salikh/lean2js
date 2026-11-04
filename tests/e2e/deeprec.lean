def sumTo : Nat → Nat
  | 0 => 0
  | n+1 => (n+1) + sumTo n

def main : IO Unit := do
  IO.println (sumTo 1000)
  IO.println (sumTo 20000)
  IO.println ((List.range 50000).foldr (· + ·) 0)
  IO.println (sumTo 100000)

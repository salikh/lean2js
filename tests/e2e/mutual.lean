mutual
def isEven : Nat → Bool
  | 0 => true
  | n+1 => isOdd n
def isOdd : Nat → Bool
  | 0 => false
  | n+1 => isEven n
end

def sumTo (n : Nat) : Nat := Id.run do
  let mut s := 0
  for i in [0:n+1] do s := s + i
  return s

partial def collatz (n : Nat) (steps : Nat := 0) : Nat :=
  if n ≤ 1 then steps
  else if n % 2 == 0 then collatz (n / 2) (steps + 1)
  else collatz (3 * n + 1) (steps + 1)

def main : IO Unit := do
  IO.println (isEven 1000)
  IO.println (isOdd 7777)
  IO.println (sumTo 100000)
  IO.println (collatz 27)

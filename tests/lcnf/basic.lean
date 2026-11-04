def double (n : Nat) : Nat := n + n

def fact : Nat → Nat
  | 0 => 1
  | n+1 => (n+1) * fact n

def greet (s : String) : String := "Hello, " ++ s

structure Point where
  x : Nat
  y : Nat

def Point.sum (p : Point) : Nat := p.x + p.y

def addAll (xs : List Nat) : Nat := xs.foldl (· + ·) 0

def mkAdder (k : Nat) : Nat → Nat := fun n => n + k

partial def loop (n : Nat) : Nat := if n > 100 then n else loop (n * 2)

def main : IO Unit := IO.println (greet "world")

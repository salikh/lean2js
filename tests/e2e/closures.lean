def compose (f g : Nat → Nat) : Nat → Nat := fun x => f (g x)
def adder (k : Nat) : Nat → Nat := fun n => n + k
def apply3 (f : Nat → Nat → Nat → Nat) := f 1 2 3

partial def loop (n acc : Nat) : Nat :=
  if n == 0 then acc else loop (n - 1) (acc + n)

def main : IO Unit := do
  IO.println ((compose (adder 3) (adder 4)) 10)
  IO.println (apply3 fun a b c => a * 100 + b * 10 + c)
  let fs := [adder 1, adder 2, adder 3]
  IO.println (fs.map (· 10))
  IO.println (loop 1000000 0)
  let partialApp := Nat.add 5
  IO.println (partialApp 6)

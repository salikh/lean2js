def f (xs : Array Nat) (i : Nat) : Nat := xs[i]!

def main : IO Unit := do
  IO.println (f #[1,2,3] 1)
  IO.println (f #[1,2,3] 10)
  IO.println ([1,2,3].head!)
  let x : Option Nat := none
  IO.println (x.getD 7)
  IO.println "after"

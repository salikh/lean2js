def fib : Nat → Nat
  | 0 => 0
  | 1 => 1
  | n+2 => fib n + fib (n+1)
#eval fib 20
structure Point where
  x : Nat
  y : Nat
  deriving Repr
#eval ({ x := 1, y := 2 } : Point)
inductive Tree where
  | leaf : Tree
  | node : Tree → Nat → Tree → Tree
def Tree.size : Tree → Nat
  | .leaf => 0
  | .node l _ r => l.size + 1 + r.size
#eval (Tree.node .leaf 3 (.node .leaf 4 .leaf)).size
theorem add_zero' (n : Nat) : n + 0 = n := by simp
#check @add_zero'
example : 2 + 2 = 4 := by decide
#eval (List.range 10).map (· * 2)
#eval s!"hello {1+1}"

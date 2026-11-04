def twice (f : Nat → Nat) (x : Nat) : Nat := f (f x)

def useTwice (k : Nat) : Nat := twice (fun n => n * k + 1) 3

inductive Tree where
  | leaf : Tree
  | node : Tree → Nat → Tree → Tree

def Tree.sum : Tree → Nat
  | .leaf => 0
  | .node l v r => l.sum + v + r.sum

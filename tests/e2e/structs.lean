structure Point where
  x : Nat
  y : Nat
  deriving Repr

inductive Shape where
  | circle (r : Nat)
  | rect (w h : Nat)
  | unit
  deriving Repr

def Shape.area : Shape → Nat
  | .circle r => 3 * r * r
  | .rect w h => w * h
  | .unit => 1

inductive Tree where
  | leaf
  | node (l : Tree) (v : Nat) (r : Tree)

def Tree.insert : Tree → Nat → Tree
  | .leaf, x => .node .leaf x .leaf
  | .node l v r, x => if x < v then .node (l.insert x) v r else .node l v (r.insert x)

def Tree.toList : Tree → List Nat
  | .leaf => []
  | .node l v r => l.toList ++ [v] ++ r.toList

def main : IO Unit := do
  let p : Point := { x := 1, y := 2 }
  IO.println (repr p)
  IO.println (repr { p with x := 10 })
  IO.println ([Shape.circle 2, .rect 3 4, .unit].map Shape.area)
  IO.println (repr (Shape.rect 3 4))
  let t := [5, 3, 8, 1, 4, 7, 9].foldl Tree.insert Tree.leaf
  IO.println t.toList

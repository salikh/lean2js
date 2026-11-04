def expensive (n : Nat) : Nat := (List.range n).foldl (· + ·) 0

def main : IO Unit := do
  let t := Thunk.mk fun _ => expensive 1000
  IO.println t.get
  IO.println t.get
  let task := Task.spawn fun _ => expensive 100
  IO.println task.get
  let t2 ← IO.asTask (pure 5)
  match t2.get with
  | .ok v => IO.println v
  | .error e => IO.println s!"err {e}"
  let tasks := (List.range 5).map fun i => Task.spawn fun _ => i * i
  IO.println (tasks.map Task.get)

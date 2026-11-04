def count (n : Nat) : Nat := Id.run do
  let mut c := 0
  for i in [0:n] do
    if i % 3 == 0 then c := c + 1
  return c

def sumList (n : Nat) : Nat := (List.range n).foldl (· + ·) 0

def main : IO Unit := do
  IO.println (count 3000000)
  IO.println (sumList 200000)
  let mut arr := Array.mkEmpty 0
  for i in [0:20000] do
    arr := arr.push i
  IO.println arr.size

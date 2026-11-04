def isSorted (xs : Array Nat) : Bool := Id.run do
  for i in [1:xs.size] do
    if xs[i-1]! > xs[i]! then return false
  return true

def lcg (s : Nat) : Nat := (s * 1103515245 + 12345) % 2147483648

def gen (n : Nat) : Array Nat := Id.run do
  let mut s := 42
  let mut a := #[]
  for _ in [0:n] do
    s := lcg s
    a := a.push (s % 1000)
  return a

def main : IO Unit := do
  let a := gen 2000
  let s := a.qsort (· < ·)
  IO.println (isSorted s)
  IO.println (s.toList.take 10)
  IO.println ((a.toList.mergeSort).take 5)
  IO.println (a.foldl max 0)
  IO.println (a.map (· % 7) |>.toList.eraseDups)
  let b := a.insertionSort (· < ·)
  IO.println (b == s)
  IO.println (Array.range 10 |>.reverse)
  IO.println (#[1,2,3].zip #["a","b","c"])
  IO.println (a.toList.partition (· < 500) |>.1.length)
  IO.println (#[3,1,2].binSearch 2 (· < ·))

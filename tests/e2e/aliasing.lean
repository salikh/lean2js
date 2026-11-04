import Std.Data.HashMap

structure S where
  arr : Array Nat
  name : String

def table : Array Nat := #[10, 20, 30]

def addAll (xs : Array Nat) (n : Nat) : Array Nat := Id.run do
  let mut r := xs
  for i in [0:n] do r := r.push i
  return r

def main : IO Unit := do
  let a := #[1, 2, 3]
  let b := a.push 4
  let c := a.push 5
  IO.println (a, b, c)
  let m : Array (Array Nat) := #[#[1], #[2]]
  let m2 := m.modify 0 (·.push 9)
  IO.println (m, m2)
  let r ← IO.mkRef #[1]
  let snap ← r.get
  r.modify (·.push 2)
  IO.println (snap, ← r.get)
  let s : S := { arr := #[1], name := "s" }
  let s2 := { s with arr := s.arr.push 2 }
  IO.println (s.arr, s2.arr)
  let f := fun (x : Nat) => a.push x
  IO.println (f 1, f 2, a)
  IO.println (table.push 4, table)
  IO.println (addAll table 3, addAll table 2, table)
  let t := Thunk.mk fun _ => a.push 100
  IO.println (t.get, t.get.push 1, t.get)
  let hm : Std.HashMap Nat (Array Nat) := ({} : Std.HashMap Nat (Array Nat)).insert 1 #[1]
  let hm2 := hm.insert 1 ((hm.getD 1 #[]).push 2)
  IO.println (hm.toList, hm2.toList)
  let arrs := (List.range 3).map fun i => (Array.range i).push 7
  IO.println arrs
  let x := #[1, 2, 3]
  let y := x.set! 0 100
  let z := x.set! 1 200
  IO.println (x, y, z)
  let w := x.pop
  IO.println (x, w, x.swapIfInBounds 0 2)

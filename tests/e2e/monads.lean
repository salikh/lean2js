def counter : StateM Nat Nat := do
  modify (· + 1)
  modify (· * 2)
  let s ← get
  set (s + 10)
  return s

def safeDiv (a b : Nat) : Except String Nat :=
  if b == 0 then .error "div by zero" else .ok (a / b)

def compute : ExceptT String (StateM Nat) Nat := do
  let s ← get
  if s > 100 then throw "too big"
  set (s + 1)
  return s * 2

def main : IO Unit := do
  let (r, s) := counter.run 5
  IO.println s!"{r} {s}"
  IO.println (repr (safeDiv 10 2))
  IO.println (repr (safeDiv 10 0))
  let (r, s) := (compute.run).run 7
  IO.println s!"{repr r} {s}"
  let (r, s) := (compute.run).run 700
  IO.println s!"{repr r} {s}"
  let o : Option Nat := do
    let a ← some 1
    let b ← none
    return a + b
  IO.println o

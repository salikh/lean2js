/-- `initialize` / `builtin_initialize`: refs, IO-unit initializers (run before `main`), IO.rand (needs IO.stdGenRef). -/
initialize counter : IO.Ref Nat ← IO.mkRef 100
initialize greeting : String ← pure "hello from initialize"
initialize IO.println "init block 1"
initialize IO.println "init block 2"
builtin_initialize bcounter : IO.Ref (Array String) ← IO.mkRef #["a"]

def bump : IO Nat := counter.modify (· + 1) *> counter.get

def main : IO Unit := do
  IO.println greeting
  IO.println (← bump)
  IO.println (← bump)
  bcounter.modify (·.push "b")
  IO.println (← bcounter.get)
  let n ← IO.rand 1 1
  IO.println n
  IO.setRandSeed 42
  let xs ← (List.range 5).mapM fun _ => IO.rand 0 1000
  IO.println xs

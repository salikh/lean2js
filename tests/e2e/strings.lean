def main : IO Unit := do
  let s := "Hello, Wörld! ∀x"
  IO.println s
  IO.println s.length
  IO.println s.utf8ByteSize
  IO.println s.toUpper
  IO.println (s.splitOn ", ")
  IO.println ("abc".append "def")
  IO.println (String.join ["a", "b", "c"])
  IO.println ("a,b,c".replace "," ";")
  IO.println ('x'.toNat)
  IO.println s.front
  IO.println (decide ("abc" < "abd"))
  IO.println ("12345".toNat?)
  IO.println ("x".isEmpty)

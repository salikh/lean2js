def main : IO Unit := do
  let stdin ← IO.getStdin
  let mut total := 0
  repeat
    let line ← stdin.getLine
    if line.isEmpty then break
    total := total + line.trimAscii.toString.toNat!
  IO.println s!"total = {total}"

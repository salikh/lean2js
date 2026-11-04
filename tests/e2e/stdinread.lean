/-- Reading all of stdin with `readToEnd` (the `read` method of the stream), including multi-byte characters. -/
def main : IO Unit := do
  let s ← (← IO.getStdin).readToEnd
  IO.println s!"{s.length} chars, {s.utf8ByteSize} bytes, {s.splitOn "\n" |>.length} parts"
  IO.print s

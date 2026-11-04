/-- File handles, metadata, stream redirection (IO.FS.withIsolatedStreams). -/
def main : IO Unit := do
  let p : System.FilePath := "/tmp/lean2js_fs_test.txt"
  IO.FS.writeFile p "line one\nline two\nünïcode\n"
  let h ← IO.FS.Handle.mk p .append
  h.putStrLn "appended"
  h.flush
  let s ← IO.FS.readFile p
  IO.println s.length
  IO.print s
  let lines ← IO.FS.lines p
  IO.println lines
  let md ← p.metadata
  IO.println s!"{md.byteSize} {repr md.type}"
  IO.println (← p.pathExists)
  IO.println (← System.FilePath.pathExists "/tmp/definitely/not/here")
  let r ← (IO.FS.readFile "/tmp/definitely/not/here").toBaseIO
  match r with
  | .ok _ => IO.println "??"
  | .error e => IO.println s!"error: {e}"
  let (out, v) ← IO.FS.withIsolatedStreams (do IO.println "captured"; IO.eprintln "err too"; return 42)
  IO.println s!"{out.length} {v}"
  let bytes ← IO.FS.readBinFile p
  IO.println bytes.size
  IO.FS.removeFile p
  IO.println (← p.pathExists)

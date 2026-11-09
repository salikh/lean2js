/-! `lake test` driver: runs `test.sh` (lcnf goldens, demo programs, infoview, e2e differential tests)
and then the headless-Chrome page tests (`web/build.sh selfhost` + `web/test-browser.sh`) when
`google-chrome` is on the PATH (set `LEAN2JS_NO_BROWSER=1` to skip them).
Arguments are passed to `test.sh`, e.g. `lake test -- --quick`. -/

def run (cmd : String) (args : Array String) : IO UInt32 := do
  let child ← IO.Process.spawn { cmd, args, env := #[("LD_LIBRARY_PATH", none)] }
  child.wait

def hasChrome : IO Bool := do
  let out ← IO.Process.output { cmd := "sh", args := #["-c", "command -v google-chrome"] }
  return out.exitCode == 0

def main (args : List String) : IO UInt32 := do
  let mut rc ← run "./test.sh" args.toArray
  if (← IO.getEnv "LEAN2JS_NO_BROWSER").isNone && (← hasChrome) then
    IO.println "== browser page tests (headless Chrome)"
    let b ← run "web/build.sh" #["selfhost"]
    if b != 0 then
      IO.println "FAIL: web/build.sh selfhost"
      rc := 1
    else if (← run "web/test-browser.sh" #[]) != 0 then
      rc := 1
  else
    IO.println "(browser page tests skipped)"
  return rc

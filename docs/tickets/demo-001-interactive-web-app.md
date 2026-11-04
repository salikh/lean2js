# Interactive web demo: Lean script + data file + console

Parent: [self-001](self-001-compiler-to-js-epic.md) (builds on the browser build in `web/selfhost/`)
Status: **done** (2026-11-05) — `web/selfhost/demo.html`, `Lean2js/Session.lean`, test `tests/e2e/session.lean`, browser test in `web/selfhost/test-browser.sh`

## Requirements (user, 2026-11-05)

1. Two input panes: the **Lean source script** and a **data JSON file**. The JSON text is exposed to the Lean runtime as a file with a fixed name (`data.json`). The script reads
   that path, computes something (average, min, max, standard deviation of a numeric sequence) and prints it.
2. Output from Lean (stdout/stderr) is intercepted and appended to a third pane, the **console**. The console also accepts **direct user input that is evaluated immediately** — in particular IO
   actions: typing `main` evaluates the `main` IO action of the script.

## Design

* **Session API** (`selfhost/Session.lean`, exported with `@[export lean2js_session_*]`): `new` imports `Init` once and returns a session object; `run session text fileName` elaborates
  commands in the session's `Command.State` (environment, namespaces, `open`s persist between inputs) and returns the new session plus the text of the messages (`#eval` output included —
  Lean's `#eval` captures `IO.println` output and reports it as an info message). The page keeps the session object; editing/re-running the script creates a new session.
* **Console input**: a line that parses as a command (`def`, `#eval`, `open`, `structure`, …) is run as is; anything else is wrapped as `#eval <line>`, so `main`, `1 + 2`,
  `stats [1,2,3]`, `IO.println "hi"` work, and an `IO` action runs its effects (reading `data.json` again, so the JSON pane can be edited between runs without re-elaborating the script).
* **Data file**: the JSON pane's text is stored in the runtime's in-memory file system (`rt.vfs`) under the key `data.json` at every edit (relative path; the Lean script uses `IO.FS.readFile "data.json"`).
* **Page** (`web/selfhost/demo.html`): left column Lean editor + JSON editor, right column console (output + input line, history with ↑/↓); buttons *Run script* (new session, elaborate, then
  run `main` if present) and *Clear*. Reuses `web/selfhost/driver.js` loading (library files into `vfs`, `elab` program). The page freezes while Lean runs (main thread, see self-hosted-elaborator.md).
* The default example parses the numbers by hand (no `import Lean`, which would require downloading the `Lean` oleans, ~1 GB): a small decimal parser + `Float` statistics.

## Tests

`selfhost/session-test.mjs` (Node; real files instead of `vfs`) drives the session API like the page does; `web/selfhost/test-browser.sh` additionally runs the default demo in headless Chrome
(`demo.html?autorun&report`) with the console line `main` and compares the console text with the expected statistics.

## Later

`import Lean` support in the browser (lazy download of more library files, Json parsing with `Lean.Json`), editor features (syntax highlighting; the infoview epic [info-001](info-001-infoview-epic.md)),
running Lean in a worker once the stack-size problem is solved.

## Result

* Page: `web/selfhost/demo.html` (build with `web/selfhost/build.sh`, serve with `node web/selfhost/serve.mjs`, open `/demo.html`). Left: Lean script (default: `examples/stats.lean`) and the `data.json` pane
  (`examples/stats.json`); right: console. *Run script* elaborates the script in a fresh session and runs `main`; console lines are evaluated in that session (`main`, `mean #[1.0, 2.0, 6.0]`, `def twice …`,
  `IO.println "x"`, errors shown with Lean's message). The JSON pane is written to the runtime's file system as `data.json` before every run/console line, so editing it and typing `main` re-reads it.
* Lean's `#eval` captures `IO.println` and reports it as a message, so output of evaluated IO actions appears in the console in order; direct writes of the runtime to stdout/stderr
  (`rt.setStdout/setStderr`) also go to the console (`.err` styling for stderr).
* Host API (usable from any page/test): `driver.js` — `loadProgram`, `newSession`, `sessionRun`, `sessionConsole`; the Lean side: `lean2js_session_new/run/console` (exports rooted by the prefix `lean2js_session_`).
  Hosts that call exports without `main` must call `rt.runInitializers()` (done by `loadProgram`) — forgetting it gives "invalid environment extension" panics.
* Known limits: the page freezes while Lean runs; `import Lean` in the script is not available in the browser (only the `Init` library files are downloaded: ~160 MB); `←` inside a console term needs `do`
  (Lean's own rule); first load ≈ 40 s locally.

# Interactive web demo: Lean script + data file + console

Parent: [self-001](self-001-compiler-to-js-epic.md) (builds on the browser build in `web/selfhost/`)
Status: in progress (2026-11-05)

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

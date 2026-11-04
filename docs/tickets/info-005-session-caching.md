# Sessions: cache the environment and snapshots

Parent: [info-001](info-001-infoview-epic.md) | Status: **basically done** (2026-11-05): the imported `Environment` lives in the `Session`; a request on a small proof costs ~65 ms in Node (first request after start ~380 ms, `selfhost/session-bench.mjs`), `Session.new` (import `Init`) ~5 s once. Not done: snapshot reuse for big files (`IO.processCommandsIncrementally … old?`) — measure on a 500-line file first.
Today a run imports `Init` (~8 s) before elaborating. The infoview needs many requests on slightly different text: keep the imported `Environment` and the header snapshot alive in a session object
(a long-lived JS program with a request loop or an exported function table), reuse the previous command snapshots for the unchanged prefix (`Language.Lean.process` takes an `old?` snapshot for
incremental reuse; `IO.processCommandsIncrementally ... old?`), and make requests cancellable/superseded cheaply. Related: self-008 (memory/startup), self-010 (scheduler).

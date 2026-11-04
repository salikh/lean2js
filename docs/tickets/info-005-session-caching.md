# Sessions: cache the environment and snapshots

Parent: [info-001](info-001-infoview-epic.md) | Status: planned
Today a run imports `Init` (~8 s) before elaborating. The infoview needs many requests on slightly different text: keep the imported `Environment` and the header snapshot alive in a session object
(a long-lived JS program with a request loop or an exported function table), reuse the previous command snapshots for the unchanged prefix (`Language.Lean.process` takes an `old?` snapshot for
incremental reuse; `IO.processCommandsIncrementally ... old?`), and make requests cancellable/superseded cheaply. Related: self-008 (memory/startup), self-010 (scheduler).

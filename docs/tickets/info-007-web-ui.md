# Web infoview

Parent: [info-001](info-001-infoview-epic.md) | Status: planned | builds on `web/selfhost/` (browser build of the frontend, main-thread run because of stack limits)
An editor pane (textarea/CodeMirror/Monaco) plus an infoview pane: goals (hypotheses, `⊢` target, multiple goals, `case` tags), messages for the cursor, hover popups;
"prefix mode" button (send the text up to the cursor) and live mode (debounced). Keep the UI in plain JS with no build step; dark/light theme as `web/index.html`.
Constraint: the frontend runs synchronously on the main thread (the page freezes while elaborating) — consider running it in a worker with a bigger stack once available, or chunking work.

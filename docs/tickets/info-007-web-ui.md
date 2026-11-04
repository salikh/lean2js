# Web infoview

Parent: [info-001](info-001-infoview-epic.md) | Status: **first version done** (2026-11-05): `web/infoview.html` (editor on the left, infoview on the right: goals, expected type, messages with the ones at the cursor marked; prefix-mode checkbox; debounced updates on keyup/click/selection change; shows the request time). Test: `web/test-browser.sh` (cursor after `constructor` → 2 goals). Later: hover popups, CodeMirror, tagged (interactive) goals — see info-006 and demo-002 (real LSP). | builds on `web/` (browser build of the frontend, main-thread run because of stack limits)
An editor pane (textarea/CodeMirror/Monaco) plus an infoview pane: goals (hypotheses, `⊢` target, multiple goals, `case` tags), messages for the cursor, hover popups;
"prefix mode" button (send the text up to the cursor) and live mode (debounced). Keep the UI in plain JS with no build step; dark/light theme as `web/index.html`.
Constraint: the frontend runs synchronously on the main thread (the page freezes while elaborating) — consider running it in a worker with a bigger stack once available, or chunking work.

# demo.html with the real LSP server and a live infoview

Parent: [demo-001](demo-001-interactive-web-app.md), [info-001](info-001-infoview-epic.md)
Status: **filed 2026-11-05 — implement after the remaining `self-*` tickets are complete** (user instruction)

## Request

Embed the **actual Lean language server** into `web/selfhost/demo.html` and add an **infoview pane that updates when the cursor moves** in the editor pane
(goals at the cursor, term goal, messages for the cursor; later hover).

## Relation to earlier decisions

[info-002](info-002-question-architecture.md) decided "thin layer over the InfoTree (option A), the real FileWorker is not planned". This ticket is a newer, explicit request for
the real server, so it **revisits that decision for the demo**: option B of info-002. The thin layer (`Lean2js/Info.lean`) stays useful as the programmer API and as a test oracle; the
two backends can coexist behind the same JSON shapes.

## Plan

1. **Server in JS.** Build `Lean.Server.FileWorker` (the per-file worker; the Watchdog's job — process management, file watching — is not needed for one document) into the self-hosted program: an
   entry point `lean2js_lsp_*` that wires the worker's `Lean.Server.Utils` I/O streams to in-memory queues instead of stdin/stdout: the page posts LSP JSON-RPC messages (`initialize`, `textDocument/didOpen`,
   `didChange`, `$/lean/plainGoal`, `$/lean/plainTermGoal`, `textDocument/hover`, `Lean.Widget.getInteractiveGoals` RPC with `RpcRef`s, `$/cancelRequest`) and reads responses/notifications
   (`textDocument/publishDiagnostics`, `$/lean/fileProgress`).
2. **Runtime needs.** The worker is a heavy user of tasks, promises, cancellation tokens, `IO.CancelToken`, `ServerTask`, `AsyncList`, `IO.Ref`s, `IO.Process`-free code paths; it expects background elaboration
   while it keeps serving requests. In the single-threaded cooperative scheduler this needs **yielding to the host event loop**: elaboration jobs run in slices (between requests, between commands) so that the page
   stays responsive and requests (cursor moves) are served promptly; today a call runs to completion and freezes the page. Depends on [self-010](self-010-promise-drop-heuristic.md) (promise semantics) and benefits from
   [self-008](self-008-bundle-startup-size.md) (startup/memory).
3. **Page.** Editor pane (textarea → CodeMirror/Monaco later) sending `didChange` on edits (debounced) and `plainGoal`/`plainTermGoal` requests on `selectionchange`/`keyup`/`click`; infoview pane showing the latest
   response for the cursor, plus the message list; keep `data.json` and the console of demo-001. Messages also drive inline error markers.
4. **Tests.** Scripted LSP transcripts through the in-memory transport compared with the native server's responses (info-008), a headless-Chrome test that moves the cursor and checks the infoview text.

## Risks

Stack depth in the browser main thread (the server code recurses a lot); memory (worker + imported environment ≈ the demo's 3 GB plus snapshots); the page freezing during elaboration unless jobs are sliced (step 2 is the critical piece);
`Lean.Server.FileWorker` imports more of `Lean` than the batch frontend (bigger JS).

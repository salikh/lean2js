# lsp.html: the real LSP server and a live infoview (a new page based on demo.html)

Parent: [demo-001](demo-001-interactive-web-app.md), [info-001](info-001-infoview-epic.md)
Status: **filed 2026-11-05 — implement after the remaining `self-*` tickets are complete** (user instruction)

## Request

Create a **new page `web/lsp.html`**, based on (a copy of) `demo.html`, that embeds the **actual Lean language server** and has an **infoview pane that updates when the cursor moves** in the editor pane
(goals at the cursor, term goal, messages for the cursor; later hover). **`demo.html` stays as it is** (user instruction 2026-11-05): no edits to it for this ticket; shared code goes to modules (`driver.js`, a new `lsp.js`) that both pages may import.

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
3. **Page `lsp.html`.** Editor pane (textarea → CodeMirror/Monaco later) sending `didChange` on edits (debounced) and `plainGoal`/`plainTermGoal` requests on `selectionchange`/`keyup`/`click`; infoview pane showing the latest
   response for the cursor, plus the message list; keep `data.json` and the console of demo-001 (copied from `demo.html`). Messages also drive inline error markers.
4. **Tests.** Scripted LSP transcripts through the in-memory transport compared with the native server's responses (info-008), a headless-Chrome test (extend `web/test-browser.sh` with an `lsp` page test) that moves the cursor and checks the infoview text; `demo.html`'s existing test must keep passing unchanged.

## Risks

Stack depth in the browser main thread (the server code recurses a lot); memory (worker + imported environment ≈ the demo's 3 GB plus snapshots); the page freezing during elaboration unless jobs are sliced (step 2 is the critical piece);
`Lean.Server.FileWorker` imports more of `Lean` than the batch frontend (bigger JS).

## Experiment 2026-11-05: the real `FileWorker` in JS (batch mode) and the blocker

`selfhost/LspBatch.lean` calls `Lean.Server.FileWorker.initAndRunWorker` with stdin/stdout/stderr streams; input = framed JSON-RPC messages (`selfhost/mklsp.mjs`), ending with `exit`.
* Natively it works (40 messages out, `$/lean/plainGoal` returns the two goals).
* In JS (transpiled with `--init-all --eval-all --small`) the worker **starts** (header setup info, progress, refresh requests) but the elaboration never completes before the main loop reaches `exit`:
  plainGoal/plainTermGoal answer `null`. Findings that needed runtime changes (all done, in `lean_rt.js`): `IO.cancel`/`IO.checkCanceled` are now real (cooperative flag of the running task);
  polling calls (`IO.hasFinished`, `getTaskState`, `IO.sleep`) run queued jobs; **dedicated tasks run lazily** (only when awaited) because the worker's refresh poller is an endless `sleep`/poll loop that,
  without preemption, starved everything below it; `LEAN2JS_WATCHDOG=<s>` prints the JS stack of a run that exceeds the limit (this is how the spin was found).
* **Root problem:** the worker is written for *concurrent* threads: a handler blocks on a task (`IO.wait`) while other tasks make progress, tasks block on each other and on promises that other
  tasks resolve later, and the main loop blocks on stdin. The cooperative scheduler runs every job to completion on the stack of whoever waits, so a job that waits for something only an interleaved
  job below it on the stack can provide cannot complete. A faithful solution needs **coroutines** (suspend a task in the middle): e.g. compile Lean code in CPS / as generator functions (slow and large),
  or one Web Worker per Lean thread with the heap shared… (not possible: JS objects cannot be shared), or a custom stack-switching runtime (WebAssembly stack switching/JSPI, not available everywhere).

## Decision needed (human)

*Question:* how should demo-002 get its "LSP server" given the blocker?
1. **(Recommended) Protocol adapter over `Lean2js.Info`:** an in-memory LSP server written in Lean (`Lean2js/Lsp.lean`: `initialize`, `didOpen`, `didChange`, `$/lean/plainGoal`, `$/lean/plainTermGoal`, `textDocument/hover`,
   `publishDiagnostics`), using the very same Lean functions as the real server for goal selection and rendering (already verified identical to `lean --server` on 9 cases). It speaks real LSP JSON-RPC, so a stock LSP
   client (Monaco + `monaco-languageclient`) could be attached later; `lsp.html` uses it with a live infoview. The responses can be compared with the real server by the existing oracle (info-008). Cost: small.
2. Coroutine-capable runtime so that the unmodified `FileWorker` runs (CPS/generator backend for `Task`-reachable code, or JSPI): large, uncertain, slow code; revisit if (1) proves insufficient.
3. Run the real worker in batch mode per request: ~10 s per request, freezes the page; not usable.

Until answered, option 1 is the default; I will not start `lsp.html` before a decision is recorded here (the question is in TODO for humans).

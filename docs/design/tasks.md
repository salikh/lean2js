# Tasks and promises in the JS runtime

JavaScript is single-threaded, so `Task`, `IO.Promise`, `BaseIO.asTask/mapTask/bindTask` use a cooperative scheduler (`runtime/lean_rt.js`):

* A **task** is finished (`pend = false`, value in `v`) or pending. Spawning (`Task.spawn`, `IO.asTask`) pushes a *job* on a FIFO queue; `Task.map/bind`
  register a continuation on the source task (`waiters`) that enqueues a job when it finishes (immediately, when `sync` is set and the source is finished).
* **Waiting** (`Task.get`, `IO.wait`, `IO.waitAny`) runs queued jobs, nested on the waiter's stack, until the awaited task is finished. A job always runs to
  completion. After `main` returns, the remaining jobs are run.
* A **promise** owns a pending task (`result?`); `resolve` finishes it with `some v`.
* **Dropped promises:** native Lean resolves `result?` with `none` when the last reference to an unresolved promise disappears. We do not observe that. When a wait finds
  the queue empty, the oldest unresolved promise is treated as dropped (resolved with `none`); `LEAN2JS_TRACE_TASKS=1` logs each such case. The elaborator relies on this
  (e.g. for tactic-block snapshot promises that are never resolved). A wrong guess could resolve a promise that the suspended outer computation was about to resolve; no
  such case has shown up so far.
* **Risk and follow-up:** see [self-010](../tickets/self-010-promise-drop-heuristic.md).
* No parallelism, priorities and cancellation (`IO.cancel` is a no-op); `getTaskState` reports waiting/finished only.

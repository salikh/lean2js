# Tasks and promises in the JS runtime

JavaScript is single-threaded, so `Task`, `IO.Promise`, `BaseIO.asTask/mapTask/bindTask` use a cooperative scheduler (`runtime/lean_rt.js`):

* A **task** is finished (`pend = false`, value in `v`) or pending. Spawning (`Task.spawn`, `IO.asTask`) pushes a *job* on a FIFO queue; `Task.map/bind`
  register a continuation on the source task (`waiters`) that enqueues a job when it finishes (immediately, when `sync` is set and the source is finished).
* **Waiting** (`Task.get`, `IO.wait`, `IO.waitAny`) runs queued jobs, nested on the waiter's stack, until the awaited task is finished. A job always runs to
  completion. After `main` returns, the remaining jobs are run.
* A **promise** owns a pending task (`result?`); `resolve` finishes it with `some v`.
* **Dropped promises:** native Lean resolves `result?` with `none` when the last reference to an unresolved promise disappears (the elaborator relies on this for cancel tokens and
  unused snapshot promises). `free()` implements exactly that (`dropPromise`, reference count reaches zero). As a fallback for leaked references, when a wait finds the queue
  empty the oldest unresolved promise is treated as dropped; both events are counted (`LEAN2JS_TIMING=1`), `LEAN2JS_TRACE_TASKS=1` logs them with the creation site, and
  `LEAN2JS_STRICT_TASKS=1` makes the fallback an error. On the test corpus the fallback never fires.
* **Risk and follow-up:** see [self-010](../tickets/self-010-promise-drop-heuristic.md).
* No parallelism, priorities and cancellation (`IO.cancel` is a no-op); `getTaskState` reports waiting/finished only.

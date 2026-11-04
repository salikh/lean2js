# Investigate: unresolved promises are guessed to be "dropped"

Parent: [self-001](self-001-compiler-to-js-epic.md) | design: [design/tasks.md](../design/tasks.md)
Status: **open — to investigate / confirm later** (filed 2026-11-05 on a side-agent review note)

## Concern

The cooperative scheduler in `runtime/lean_rt.js` (`waitFor`) has a heuristic of last resort: when a task waits, the job queue is empty and the awaited task is still pending, the
**oldest unresolved promise is resolved with `none`**, as native Lean does for a promise whose last reference is dropped. We do not observe drops (no finalizers on our RC), so this
is a guess. If the guess is wrong (the promise would have been resolved later by a computation that is suspended further down the JS stack), the self-hosted elaborator can produce
**wrong or incomplete output without any error**. The firing is logged only with `LEAN2JS_TRACE_TASKS=1`.

Until this ticket is resolved, treat the output of the self-hosted frontend as *unverified beyond the differential tests* (`tests/e2e/selfhost*.lean`: identical to native on
`selfhost/sample.lean`, `sample2.lean`, `sample3.lean`).

## Evidence so far

* Without the heuristic, `selfhost/sample2.lean` (structure, inductive type, `simp`, `decide`, `deriving Repr`) deadlocks in `SnapshotTree.getAll`; with it the output is byte-identical
  to native. `LEAN2JS_TRACE_TASKS=1` shows it fires roughly once per command (many times in total).
* Counts (`LEAN2JS_TIMING=1` prints `dropped-promise guesses: N`): `selfhost/sample.lean` (4 simple commands) needs **0** guesses (`LEAN2JS_STRICT_TASKS=1` passes);
  `sample2.lean` needs **36**. `LEAN2JS_STRICT_TASKS=1` makes the heuristic an error.
* No case of a wrong guess has been observed, but the test corpus is small.

## Investigation plan

1. **Count and classify**: log (with `LEAN2JS_TRACE_TASKS`) creation site and the waiting site of every promise resolved by the heuristic; check whether they are all promises that native
   Lean also never resolves (e.g. snapshot promises of commands without incremental elaboration, `Elab.async` result promises that are dropped).
2. **Strict mode**: add `LEAN2JS_STRICT_TASKS=1` that turns the heuristic into an error; run all e2e/selfhost tests and larger inputs (e.g. the `Init` sources, Mathlib-style files) and list the firings.
3. **Real fix**: track drops. Options: (a) make `dec`/`free` of a `Promise_` object resolve it with `none` when its reference count reaches zero (needs exact RC for promises; our RC is
   conservative — we leak references in places, so some drops would be missed and the heuristic would stay as fallback); (b) `FinalizationRegistry` on the promise object (non-deterministic timing,
   cannot run while the scheduler is waiting synchronously — useless); (c) audit which Lean call sites create promises that may be dropped and handle those explicitly.
4. **Differential corpus**: compare the self-hosted output with native on many inputs (the `tests/e2e/*.lean` sources themselves, `demo/*.lean`, Init/Std files that elaborate stand-alone).
5. Decide: remove the heuristic if (a) is exact enough, otherwise keep it behind the trace/strict flags and document the residual risk in README.

## Done when

The firings are explained (each corresponds to a promise that native Lean drops or never resolves), a strict mode exists and passes on the corpus, or the root cause is fixed by drop tracking.

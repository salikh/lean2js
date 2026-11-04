# Investigate: unresolved promises are guessed to be "dropped"

Parent: [self-001](self-001-compiler-to-js-epic.md) | design: [design/tasks.md](../design/tasks.md)
Status: **resolved** (2026-11-05): dropped promises are detected by reference counting; the fallback never fired on a 38-file corpus (`tests/selfhost-corpus.sh`: demos, examples and the e2e programs elaborated by the JS frontend in strict mode, output identical to native, 0 guesses). The fallback stays as a safety net against hangs but now prints a one-time warning on stderr; reopen if the warning ever shows up. Originally filed on a side-agent review note.

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

## Result of the investigation (2026-11-05)

* The promises that were "guessed dropped" are by design never resolved by the elaborator and rely on Lean's drop semantics: the internal promise of `IO.CancelToken.new` (cancellation that never happens),
  the snapshot promises of `elabMutualDef` (`bodyPromises`/`tacPromises` when no incremental reuse happens), `runLintersAsync`, `parseCmd` snapshot promises.
* **Fix (step 3a):** `free()` in `lean_rt.js` now resolves the task of an unresolved `Promise_` with `none` when its reference count reaches zero (`dropPromise`), exactly at the moment native Lean does.
  On `selfhost/sample2.lean`: **32 promises dropped by reference counting, 0 heuristic guesses** (before: 36 guesses). The heuristic remains only as a fallback for leaked references; it is counted
  (`LEAN2JS_TIMING=1` prints both numbers) and `LEAN2JS_STRICT_TASKS=1` turns it into an error. The selfhost tests now run with `LEAN2JS_STRICT_TASKS=1` (`tests/e2e/selfhost*.env`).
* Verified: `sample.lean`, `sample2.lean`, `sample3.lean` produce output identical to native with strict tasks.
* Open: a larger corpus (step 4) — run the elaborator over many inputs in strict mode and see whether the fallback ever fires; if never, delete it.

## Corpus result (2026-11-05)

`tests/selfhost-corpus.sh` — 38 files, 0 differences from native, 0 dropped-promise guesses (strict tasks). Done criteria met; remove the fallback if no warning is ever reported over a longer period.

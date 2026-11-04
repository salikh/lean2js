# Epic: LCNF → JavaScript transpiler

Status: **in progress** — core transpiler, runtime and 22 differential tests work (2026-11-04); see docs/design/js-transpiler.md and the status of each subticket.

## Goal

Execute compiled Lean 4 programs in a web browser (and Node) by transpiling
Lean's LCNF (as dumped by `lcnf-dump`, see
[lcnf-001-json-dump](lcnf-001-json-dump.md) and
[docs/design/lcnf-json.md](../design/lcnf-json.md)) to JavaScript, plus a small
JavaScript runtime library implementing Lean's primitives.

Target pipeline:

    File.lean --lcnf-dump--> File.json --lean2js--> File.js (+ runtime.js) --node/browser--> output

## Background

* The existing dump contains only declarations defined in the input file.
  Calls to library functions (`Nat.add`, `String.append`, `IO.getStdout`,
  `List.foldl`, ...) appear as `const` references with no body. The transpiler
  needs (a) the bodies of reachable imported functions that are implemented in
  Lean ([js-006](js-006-dump-dependencies.md)) and (b) a JS implementation of
  `@[extern]`/builtin primitives ([js-008](js-008-runtime-core.md),
  [js-009](js-009-runtime-io.md)).
* Pure LCNF (base/mono) node kinds that must be handled: `let` (values: `lit`,
  `erased`, `proj`, `const`, `app`), `fun` (local closure), `jp`/`jmp` (join
  points), `cases`, `return`, `unreach`. Impure phase adds explicit
  `ctor`/`oproj`/`box`/`inc`/`dec`/... (see design doc).
* Lean semantics to keep in mind: strict evaluation, arbitrary-precision `Nat`/`Int`,
  fixed-width `UInt8/16/32/64/USize`, `Char` = `UInt32`, UTF-8 `String`, persistent-by-default
  immutable data (destructive update is only an optimization), tail calls that must not
  overflow the stack, `partial def` loops, thunks, tasks, `IO` as a state-token function.

## Subtickets (suggested order)

Questions (decided; recommended answers were accepted; js-002 was decided by the user, js-003..005 were accepted as recommended):

* [js-002-question-implementation-language](js-002-question-implementation-language.md)
* [js-003-question-input-phase](js-003-question-input-phase.md)
* [js-004-question-value-representation](js-004-question-value-representation.md)
* [js-005-question-tail-calls](js-005-question-tail-calls.md)

Work:

1. [js-006-dump-dependencies](js-006-dump-dependencies.md) — extend `lcnf-dump` with transitive imported decls and inductive-type metadata.
2. [js-007-codegen-core](js-007-codegen-core.md) — the transpiler proper (pure core language → JS).
3. [js-008-runtime-core](js-008-runtime-core.md) — runtime: Nat/Int/UIntN/Char/String/Array/ByteArray/Float primitives.
4. [js-009-runtime-io](js-009-runtime-io.md) — runtime: IO, ST.Ref, panic, stdout/stderr/stdin, Thunk, Task, files.
5. [js-010-cli-bundling](js-010-cli-bundling.md) — `lean2js` command, entry-point wiring, browser/Node bundle.
6. [js-011-end-to-end-tests](js-011-end-to-end-tests.md) — differential tests: native Lean output vs JS output.
7. [js-012-array-updates](js-012-array-updates.md) — in-place Array updates (done via js-013).
8. [js-013-question-ir-backend](js-013-question-ir-backend.md) — IR (λRC) backend with reference counting (done, default).
9. [js-014-cleanup-gaps](js-014-cleanup-gaps.md) — retire/dedupe the mono backend, remaining runtime gaps.

Dependencies: 007 needs 002–005 decided (provisional answers suffice) and 006 for
non-trivial programs; 008/009 can proceed in parallel with 007; 010 needs 007; 011 grows
alongside everything.

## Done when

A non-trivial Lean program (e.g. one using `List`, `Array`, `String`, `HashMap`, `IO.println`,
structures, inductives, closures, `partial def`) is compiled to JS and produces output identical to
the natively compiled program under Node, and runs in a browser page. Update README.md,
docs/design/ (new `js-transpiler.md`), docs/CHANGES.md.

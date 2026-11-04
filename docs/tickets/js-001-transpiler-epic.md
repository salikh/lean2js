# Epic: Lean → JavaScript transpiler (source: Lean IR, originally LCNF)

Status: **core done** (2026-11-04) — 32 differential e2e tests pass; open items are in js-008…js-011 and
[js-014](js-014-cleanup-gaps.md). Design: [docs/design/js-transpiler-ir.md](../design/js-transpiler-ir.md).

> **Change of source language (2026-11-04).** This epic started from mono-phase LCNF (JSON dumped by `lcnf-dump`). After
> [js-013](js-013-question-ir-backend.md) the transpiler takes Lean's **final IR (λRC, with reference counting)** straight from the
> elaborated environment (`lean2js FILE.lean`, in-process, no JSON step). Reason: only the IR carries ownership information
> (`inc`/`dec`/borrowed params/`reset`/`reuse`), which makes `Array` updates in place (js-012: 55 s → 0.14 s). The mono-LCNF
> backend (`Codegen.lean`, `Ast.lean`, `lean_runtime.js`, JSON input, `--backend mono`) was **removed** (js-014 item 1) and survives
> only in the jj history. `lcnf-dump` stays as a standalone inspection tool. Text below that talks about LCNF/JSON describes the
> original plan; the subtickets js-006/js-007 are historical in that respect (their notes say what was reused).

## Goal

Execute compiled Lean 4 programs in a web browser (and Node) by transpiling
Lean's IR (originally: LCNF as dumped by `lcnf-dump`, see
[lcnf-001-json-dump](lcnf-001-json-dump.md) and
[docs/design/lcnf-json.md](../design/lcnf-json.md)) to JavaScript, plus a small
JavaScript runtime library implementing Lean's primitives.

Target pipeline (current):

    File.lean --lean2js (elaborates in-process, reads IR)--> File.js (+ lean_rt.js, lean_expr.js) --node/browser--> output

Original plan (superseded): `File.lean --lcnf-dump--> File.json --lean2js--> File.js`.

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
8. [js-013-question-ir-backend](js-013-question-ir-backend.md) — IR (λRC) backend with reference counting (done, the only backend).
9. [js-014-cleanup-gaps](js-014-cleanup-gaps.md) — mono backend removed; remaining runtime gaps.

Follow-on epic: [self-001-compiler-to-js-epic](self-001-compiler-to-js-epic.md) (run the Lean compiler itself in JS).

Dependencies: 007 needs 002–005 decided (provisional answers suffice) and 006 for
non-trivial programs; 008/009 can proceed in parallel with 007; 010 needs 007; 011 grows
alongside everything.

## Done when

A non-trivial Lean program (e.g. one using `List`, `Array`, `String`, `HashMap`, `IO.println`,
structures, inductives, closures, `partial def`) is compiled to JS and produces output identical to
the natively compiled program under Node, and runs in a browser page (**achieved**, see web/examples/calc.lean). README.md,
docs/design/js-transpiler-ir.md and docs/CHANGES.md are up to date.

# Question: How to avoid JS stack overflow on tail calls / deep recursion?

Parent: [js-001-transpiler-epic](js-001-transpiler-epic.md)

Status: **decided (2026-11-04)**: the recommended answer was accepted. Reopen by moving this ticket to "TODO for humans" in TODO.md.

## Question

JS engines do not guarantee tail-call elimination, and have small stacks (~10k frames). Lean
programs rely on tail calls in loops (`partial def loop`, `List.foldl`, `forIn`), and the
native compiler turns self tail calls into loops.

## Recommended answer

Phase 1: compile self-tail-calls (function ends with `let x := f args; return x` for the same `f`,
including through `jp`s) to `while (true)` loops with parameter reassignment; `jmp` to join points
compile to labeled blocks / local functions. Leave non-self tail calls (mutual recursion,
`bind` chains in `IO`) as ordinary calls. Phase 2 (only if tests need it): trampoline for
mutual-tail-call SCCs. Deep non-tail recursion remains limited by the JS stack; document it
(Node: `--stack-size`).

## Alternatives

* Trampolining everything (slow, ugly generated code).
* CPS/async generators (very slow).

## If revised

Affects js-007 only.

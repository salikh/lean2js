# Question: Which LCNF phase to dump?

Parent ticket: [lcnf-001-json-dump](lcnf-001-json-dump.md)

Status: **decided (2026-11-04)**: the recommended answer was accepted. Reopen by moving this ticket to "TODO for humans" in TODO.md.

## Question

LCNF has `base` (typed, pre-monomorphization), `mono` (monomorphized, closest to codegen for the pure pipeline) and, in Lean 4.35, an `impure` phase (explicit ctor/proj/boxing/RC). Which should the dump command output by default?

## Recommended answer (currently implemented)

Default `mono`; `--phase base|mono|impure` selects another one. Mono is the final pure form and the simplest input for an interpreter / JS transpiler.

## Decision

Proceed with `mono` stage (lean2js may assume the input from the mono stage, the dump should still work with any of the stages).

## Alternatives

`impure` is lower level (explicit reference counting and boxing), useful for a C-like backend but noisy for JS. `base` retains polymorphism.

## If revised

Change the default in `LcnfDump.lean` (`defaultPhase`) and goldens in `tests/lcnf/`.

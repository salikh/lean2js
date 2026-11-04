# Question: In which language to implement the transpiler?

Parent: [js-001-transpiler-epic](js-001-transpiler-epic.md)

Status: **decided by the user (2026-11-04)**: the transpiler is implemented in Lean 4. No further input needed.

## Question

The transpiler reads the LCNF JSON and emits JS. It could be written in Lean, in
JavaScript/TypeScript, or another language.

## Recommended answer

Lean, as a new `lean_exe` (`lean2js`) in this project: reads JSON via `Lean.Json`, reuses
the project toolchain (no Node/npm build dependency for the compiler), and could later
consume LCNF directly from the environment (skipping JSON) or be self-hosted in the
browser. Runtime library (`runtime.js`) is hand-written plain JS (ES modules, no build step).

## Alternatives

* TypeScript/Node: easier JS string manipulation and source maps, but adds an npm toolchain.
* Python script: quick prototype, but a third toolchain.

## If revised

Affects js-007, js-010 only; the JSON interface is language-neutral.

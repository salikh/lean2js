# Dump imported dependencies and inductive metadata in `lcnf-dump`

Parent: [js-001-transpiler-epic](js-001-transpiler-epic.md)

Status: open

## Goal

Extend `lcnf-dump` (see [lcnf-001](lcnf-001-json-dump.md), `Lean2js/LcnfDump.lean`) so its output is
sufficient to run a program standalone:

1. `--with-deps`: also dump the LCNF of every declaration *transitively reachable* from the file's
   declarations (following `const` references and `pap`/`fap`), including those imported from
   `Init`/`Std`/`Lean`. Imported decls come from the persistent extension data:
   `Lean.Compiler.LCNF.getDeclCore? env monoExt name` (works for imported modules; look at
   `PhaseExt.lean`). Note bodies of non-`@[inline]`/non-transparent public decls may be replaced by
   `.extern { entries := [.opaque] }` on export (`exportEntriesFnEx` in `PhaseExt.lean`) — investigate
   whether `Init` decls have usable mono bodies in 4.35 or only IR (`Lean.IR` decls via
   `Lean.IR.findEnvDecl`). If mono bodies are unavailable for imported modules, fall back to dumping
   the `Lean.IR` (λRC) declarations for dependencies and make a ticket about transpiling IR; **report
   findings in this ticket** — this decides the architecture of the whole epic.
2. Mark every dumped decl with its origin module (`"module"`), and list unresolved references
   (builtin/extern primitives with no body) in a top-level `"externs"` array with the extern entry
   data (`@[extern "lean_nat_add"]` → C symbol name) and the arity/type.
3. `"inductives"`: for each inductive type used in `cases`/ctor calls: name, ctor list with `cidx`,
   number of relevant fields, field types, and flags (enumeration-like, structure-like, builtin repr).
   Source: `Lean.getConstInfoInduct`, `Lean.Compiler.LCNF.getCtorLayout`/`CtorInfo`
   (`toIRType`-like info lives in `Lean.IR`/`ToIR`).
4. Bump `schemaVersion`, update docs/design/lcnf-json.md, add golden tests.

## Acceptance

`lcnf-dump tests/lcnf/basic.lean --with-deps` contains bodies for `List.foldl` etc. and an `externs`
list containing `Nat.add`, `String.append`, `IO.getStdout`..; `inductives` has `Point`, `List`, `Option`.

# Question: Which declarations to include in the dump?

Parent ticket: [lcnf-001-json-dump](lcnf-001-json-dump.md)

Status: **decided (2026-11-04)**: the recommended answer was accepted. Reopen by moving this ticket to "TODO for humans" in TODO.md.

## Question

The pipeline generates auxiliary declarations (`_closed_N`, `_lambda_N`, `_spec_N`, `_redArg`...) besides the user's declarations.

## Recommended answer (currently implemented)

Include everything the pipeline stored for the file's own module, in name order, without special marking (they are ordinary decls for a backend).

## Alternatives

Only user-written decls; or mark auxiliary ones with a flag.

## If revised

Change filtering in `Lean2js/LcnfDump.lean`.

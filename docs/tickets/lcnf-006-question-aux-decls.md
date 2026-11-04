# Question: Which declarations to include in the dump?

Parent ticket: [lcnf-001-json-dump](lcnf-001-json-dump.md)

Status: **provisionally decided and implemented** (revise if you disagree)

## Question

The pipeline generates auxiliary declarations (`_closed_N`, `_lambda_N`, `_spec_N`, `_redArg`...) besides the user's declarations.

## Recommended answer (currently implemented)

Include everything the pipeline stored for the file's own module, in name order, without special marking (they are ordinary decls for a backend).

## Alternatives

Only user-written decls; or mark auxiliary ones with a flag.

## If revised

Change filtering in `Lean2js/LcnfDump.lean`.

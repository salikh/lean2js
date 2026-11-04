# Question: Pretty vs compact JSON output?

Parent ticket: [lcnf-001-json-dump](lcnf-001-json-dump.md)

Status: **provisionally decided and implemented** (revise if you disagree)

## Question

Should the command emit indented or compact JSON?

## Recommended answer (currently implemented)

Pretty (indented) by default for diffable goldens; `--compact` flag for single-line output.

## Alternatives

Compact by default.

## If revised

Flip default in `LcnfDump.lean`.

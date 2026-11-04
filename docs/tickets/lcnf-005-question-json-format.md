# Question: Pretty vs compact JSON output?

Parent ticket: [lcnf-001-json-dump](lcnf-001-json-dump.md)

Status: **decided (2026-11-04)**: the recommended answer was accepted. Reopen by moving this ticket to "TODO for humans" in TODO.md.

## Question

Should the command emit indented or compact JSON?

## Recommended answer (currently implemented)

Pretty (indented) by default for diffable goldens; `--compact` flag for single-line output.

## Alternatives

Compact by default.

## If revised

Flip default in `LcnfDump.lean`.

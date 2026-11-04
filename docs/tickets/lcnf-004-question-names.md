# Question: How to encode Lean `Name`s in the JSON?

Parent ticket: [lcnf-001-json-dump](lcnf-001-json-dump.md)

Status: **decided (2026-11-04)**: the recommended answer was accepted. Reopen by moving this ticket to "TODO for humans" in TODO.md.

## Question

Names can have numeric components and components containing dots (e.g. `«a.b»`, `_private.Foo.0.bar`).

## Recommended answer (currently implemented)

Dotted string via `Name.toString` (escaped form), e.g. `"Foo.bar._lambda_1"`. Readable; ambiguity only in pathological cases.

## Alternatives

Array of components (`["Foo","bar",{"num":1}]`): unambiguous but verbose.

## If revised

Change `nameToJson` in `Lean2js/LcnfJson.lean`; bump schema `version`.

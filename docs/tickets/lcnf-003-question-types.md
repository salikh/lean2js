# Question: How to represent LCNF types in the JSON?

Parent ticket: [lcnf-001-json-dump](lcnf-001-json-dump.md)

Status: **decided (2026-11-04)**: the recommended answer was accepted. Reopen by moving this ticket to "TODO for humans" in TODO.md.

## Question

LCNF declarations, params and let-decls carry (erased) types as `Expr`. How should they be serialized?

## Recommended answer (currently implemented)

Pretty-printed strings (`Expr` rendered by `ppExpr`-like fallback; erased type as `"◾"`). Backends rarely need types after mono.

## Alternatives

Full structural `Expr` JSON (bigger, more work, lossless). Both (`type` string + `typeExpr`).

## If revised

Change `Lean2js/LcnfJson.lean` type serializer; bump schema `version`.

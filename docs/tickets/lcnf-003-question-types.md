# Question: How to represent LCNF types in the JSON?

Parent ticket: [lcnf-001-json-dump](lcnf-001-json-dump.md)

Status: **provisionally decided and implemented** (revise if you disagree)

## Question

LCNF declarations, params and let-decls carry (erased) types as `Expr`. How should they be serialized?

## Recommended answer (currently implemented)

Pretty-printed strings (`Expr` rendered by `ppExpr`-like fallback; erased type as `"◾"`). Backends rarely need types after mono.

## Alternatives

Full structural `Expr` JSON (bigger, more work, lossless). Both (`type` string + `typeExpr`).

## If revised

Change `Lean2js/LcnfJson.lean` type serializer; bump schema `version`.

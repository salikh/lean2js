# LCNF JSON dump

Command: `lake exe lcnf-dump FILE.lean [--phase base|mono|impure] [--compact] [--out OUT.json]`

Implementation:

* `LcnfDump.lean` — CLI entry point (`lcnf-dump` exe, `supportInterpreter = true`
  is required because the file is elaborated, and `#eval`/`initialize` may run code).
* `Lean2js/LcnfDump.lean` — elaborates the file with `Lean.Elab.runFrontend`
  (messages are redirected to stderr, so stdout carries only JSON), then reads the
  declarations from the LCNF environment extensions `baseExt` / `monoExt` /
  `impureExt` (state = decls defined locally in the file, imports excluded).
* `Lean2js/LcnfJson.lean` — `Decl`/`Code`/`LetValue`/... → `Json` serializer, generic
  over `Purity`.
* Tests: `tests/run.sh` (golden files `tests/lcnf/*.mono.json`; `--update`
  regenerates). Covers literals, cases, recursion, structure projections, closures,
  inductives, specialization, `IO`, `partial def`, and the error case.

Lean 4.35 specifics: the new compiler is the default, and LCNF has three phases:
`base` (pure, typed), `mono` (pure, monomorphized; default for the dump) and `impure`
(explicit `ctor`/`oproj`/`box`/`inc`/`dec`..., includes `_boxed` wrappers).

Exit status: 0 success; 1 elaboration failed (nothing on stdout); 2 bad usage.

## Schema (version 1)

Top level: `{"version": 1, "leanVersion": str, "file": str, "phase": str, "decls": [Decl]}`.
Decls are sorted by name. Object key order is not significant (and is whatever
`Json` printing yields; deterministic).

Names (`name`, `ctor`, `typeName`, ...) are dotted strings
([lcnf-004-question-names](../tickets/lcnf-004-question-names.md)). Types are strings, erased types appear
as `lcErased`/`lcAny`/`lcVoid` ([lcnf-003-question-types](../tickets/lcnf-003-question-types.md)).
Free variables/join points are referenced by id string (`"_uniq.N"`), unique within a
declaration.

`Decl`: `name`, `levelParams: [str]`, `type`, `params: [Param]`, `recursive`, `safe`,
`inline` (null | `inline`|`noinline`|`macro_inline`|`inline_if_reduce`|`always_inline`),
`value`: `{kind:"code", body: Code}` or `{kind:"extern", entries:[{kind:"adhoc"|"inline"|"standard"|"opaque", ...}]}`.

`Param`: `{id, name, type, borrow}`. `FunDecl`: `{id, name, params, type, body}`.

`Arg`: `{kind:"erased"}` | `{kind:"fvar", id}` | `{kind:"type", type}`.

`Code` (each node has `kind`):

| kind | fields |
|---|---|
| `let` | `id, name, type, value: LetValue, body` |
| `fun` / `jp` | `decl: FunDecl, body` |
| `jmp` | `jp, args` |
| `cases` | `typeName, resultType, discr, alts: [Alt]` |
| `return` | `var` |
| `unreach` | `type` |
| impure only: `oset uset sset setTag inc dec del` | see `Lean2js/LcnfJson.lean` |

`Alt`: `{kind:"alt", ctor, params, body}` (pure), `{kind:"ctorAlt", info, body}`
(impure), `{kind:"default", body}`.

`LetValue` (`kind`): `lit` (`lit: {kind: nat|str|uint8|..., value}`), `erased`,
`proj` (`typeName, idx, struct`), `const` (`name, levels, args`), `app` (`fn, args`;
application of a local variable), and impure-only `ctor oproj uproj sproj fap pap
reset reuse box unbox isShared`.

## Changing decisions

The provisional design choices are tracked in `docs/tickets/lcnf-*.md`. Bump
`schemaVersion` in `Lean2js/LcnfJson.lean` and regenerate goldens (`tests/run.sh --update`)
on any schema change.

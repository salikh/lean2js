# Bundle, startup time and size

Parent: [self-001](self-001-compiler-to-js-epic.md)
Status: open — **gate for the first end-to-end milestone** ([self-009](self-009-milestone-hello-elab.md)): the milestone is not "done" until the
page/bundle size and startup time below are acceptable.

## Measurements (2026-11-04)

| program | flags | generated JS |
|---|---|---|
| `Lean.Elab.runFrontend` probe, no initializers | – | **21 MB**, ~12k functions |
| `tests/e2e/mvars.lean` (`import Lean`, MetaM) | `--init-all` | **327 MB**, ~4.7 M lines (≈ 5000 init decls pull in every builtin parser/elaborator/tactic) |

`--init-all` run time: transpile ≈ 20 s, load + run of mvars ≈ 10 s in Node. A browser cannot download/parse 327 MB, so the plain
"emit everything" approach does not ship. (Side-agent note, accepted.)

## Ideas, roughly in order of payoff

1. **Run only the init steps a program needs** (demand-driven): e.g. skip `_regBuiltin` registrations for tactics/elaborators the page never uses;
   needs a per-feature profile (an "elaborator for `def`/`#eval` only" build) — the native binary cannot do this, we can since we control the roots.
2. **Lazy loading**: split output per module (ES modules, `import()` on first call of a function of that module); keep a small eager core.
3. **Minify** (identifier mangling, drop `rt.` prefixes via local aliases, shorter object keys `a0`…); target ≥ 3× smaller; then brotli/gzip.
4. **Run initializers at build time and ship their results** (user idea, 2026-11-04; supersedes "snapshot after startup"). The transpiler (or a
   build step running the generated JS under Node) executes the init steps once, then serializes the resulting heap — every init constant
   and everything reachable from it: parser tables, attribute/extension registries, option decls, `IO.Ref` contents, `_closed_N` constants.
   Needs a graph serializer for our object model (ctor objects, arrays, bigints, strings, scalars; sharing preserved by object ids;
   `Clo` serialized as (function id, arity, args), so every function that can be a closure target gets a stable id in an exported table;
   `rc` re-initialized to 0 = persistent). Effects:
   * removes the **time** of running ~5000 initializers and all code that exists only to run them (initFns, `_regBuiltin` thunks, `registerX` helpers
     once nothing else references them) — modest code saving;
   * does **not** by itself shrink the elaborator/parser/tactic code, because snapshot closures still point at it. The real size win comes from
     combining it with item 2: the snapshot names functions by id, so function bodies can be fetched **lazily per module chunk** on first call.
   * Must not snapshot steps whose result depends on the host or run: time, random seeds (`IO.stdGenRef` is deterministic but seeded from
     `IO.getRandomBytes`? check), env vars, process ids, tasks/promises, file handles. Mark such init decls "runtime-only" (a deny list) and
     keep them as normal startup steps.
   * Partial evaluation variant (cheaper first step): evaluate only *pure closed constants* (`_closed_N`, zero-arity non-init constants) at build time and emit
     them as JSON/JS literals instead of code.
5. Tree-shake harder (dead-branch elimination, drop `_boxed` wrappers never called, share `_closed_N` constants).

## Acceptance for the gate

Agree numbers with the user, provisional: ≤ ~40 MB uncompressed / ≤ ~8 MB brotli for the elaborator without Mathlib-like imports, cold start
to first `#check` ≤ ~10 s in Chrome. Record the achieved numbers here and in `docs/design/`.

Related: js-014 item 4 (`--bundle`).

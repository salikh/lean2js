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

## Progress (2026-11-05)

Measured with `selfhost/Elab.lean` (`--init-all --eval-all`), Node 24, input `def x := 1 / #check / #eval / theorem`:

| | before | now |
|---|---|---|
| JS size | 452 MB | **174 MB** with `--small` (short ids `_<base36>`, no indentation; the long-name → short-id table for `evalConst` is included) |
| brotli (estimated from a 40 MB sample) | – | **~14 MB** (gzip would be ~30 MB) |
| run time (cold, whole run incl. elaboration) | ~40 s | **~14 s**: load 4.5 s, initializers 1.4 s, `importModules Init` + elaboration 8 s |
| RSS | – | 2.8 GB (3.4 GB without `--small`) |

What got faster: `lean_olean.js` (region lookup by binary search instead of a linear scan over thousands of regions: 28 s → 7 s; 32-bit header/pointer reads and fixed-shape
object literals: 2× on top; ~180 MB/s now), `string_hash` without allocation. Node's compile cache (`NODE_COMPILE_CACHE=dir`) saves ~1.7 s on warm runs.

Revised view of the gate: download size is fine (brotli ~14 MB, comparable to the official wasm builds), **memory (≈ 3 GB) and the 14 s start are the open problems**.
Next ideas, by payoff: (1) lazy decoding of `.olean` regions (`.server` and `.ir` parts and most constants are never touched: ~1 GB of JS objects today),
(2) lazy loading of code chunks by module (needs a synchronous loader or an async entry), (3) snapshotting the post-initialization state (see item 4 above),
(4) prune `--eval-all` to modules whose declarations can be reached by attributes (macros/parsers) instead of everything.

## Progress (2026-11-05, later)

`lean_olean.js`: the offset → object tables of `.olean.private` and `.ir` regions are released after parsing (nothing points into them), and the scalar areas of constructors are copied into a compact
per-region pool so the file images can be garbage collected. Measured (`--small`, sample.lean): external memory 737 → 439 MB, run time 14 → 11.7 s, RSS ≈ 2.6 GB (JS heap 1.5 GB is the decoded objects).
The remaining big item is the decoded object graph itself (`.olean.private` is 258 MB of the 384 MB of `Init` files): lazy decoding of constants' bodies (shell objects with accessor fields, subtree sizes from a
pre-pass) is the next idea; smaller objects (drop `n`/`rc`, merge `sbuf`/`soff`) another.

# Bundle, startup time and size

Parent: [self-001](self-001-compiler-to-js-epic.md)
Status: **practical gate met** (2026-11-05): 174 MB JS (~14 MB brotli), ~11 s for a complete small run in Node, ~42 s including the download in headless Chrome, ≈ 2.6 GB RSS; the browser demos work. Further optimizations (below) are optional. Original status: open — **gate for the first end-to-end milestone** ([self-009](self-009-milestone-hello-elab.md)): the milestone is not "done" until the
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

## Question (human): is more memory/startup work wanted? — filed 2026-11-05

Current state: 174 MB JS (~14 MB brotli), ~11 s Node run, ≈ 2.6 GB RSS, ~42 s in headless Chrome including a 160 MB library download. The browser demos work. Remaining ideas are costly:
lazy decoding of `.olean` constants (shell objects with accessor fields, a pre-pass for subtree sizes; maybe −40% memory, risky for the generated code's field access), lazy loading of code chunks per module (needs an async/sync
loader design), a post-initialization heap snapshot (big serializer). **Recommended: no further work now** — revisit when `import Lean` in the browser (≈ 1 GB of library files) or mobile devices matter.
Please answer: stop here (recommended), or pick one of the ideas?

## Answer

Need to analyze additional ideas, e.g. about bundling the multiple files into one download, and making more initialization lazy, and maybe making download itself lazy for some parts. Do the analysis for more way to optimize and ask me again later.

## Analysis of further optimization ideas — 2026-11-06 (answer to the above; no implementation)

The human asked for an analysis of more ways to optimize (bundling downloads, lazy initialization, lazy downloads) and to be asked again later. Status of the question: **answered, follow-up analysis below; decision
on which idea to implement is requested again at the end.**

Where the cost is today (Init-only library in `web/lib`: 653 modules x 5 parts = 3265 files, 385 MB raw; `elab.js` 174 MB):

| part | size | needed when |
|---|---|---|
| `.olean.private` | 258 MB | bodies/proofs of private and non-exposed constants: touched rarely (kernel checks, `#print`, `unfold`) |
| `.olean` | 96 MB | exported constants, the environment extensions: `importModules` reads all of it |
| `.ir` | 18 MB | IR for `evalConst`/`#eval` of imported decls (only when interpreting, but the JS `--eval-all` code replaces most of it) |
| `.olean.server` | 12 MB | server-only (info-trees docstrings etc.): never touched by `elab`/`demo`, needed for hover docstrings |
| `elab.js` | 174 MB (~14 MB brotli) | parsed and compiled on load; initializers run all of it |

Ideas, grouped by what they save (all numbers are estimates to be confirmed by a measurement before building anything):

1. **One download instead of 3265 requests (bundling).** Pack the library into a single `lib.bin` (index + concatenated files), brotli-compressed on the server side (`Content-Encoding: br`; the `.olean` files compress ~4x), fetched
   as one stream and parsed incrementally as it arrives (the loader is a pure function of bytes, so parsing can overlap the download). Removes per-request overhead (today a pool of 12 fetches) and gives a progress bar.
   Saves: download time and request count; **not** memory. Cost: small (a build step + a loader change in `driver.js`). Also fixes the "thousands of fetches" fragility for `import Lean` (~1 GB, 3x the files).
2. **Lazy download of parts.** `.olean.server` (12 MB) and `.ir` (18 MB) are not needed until hover docstrings / `evalConst` of a library decl; `.olean.private` (258 MB, two thirds of the library!) is needed only when
   a constant body is demanded. Fetch them on first use: needs a *synchronous* access point (the Lean code calls `readModuleData` synchronously) -- either blocking on a prefetch started in the background (the page starts the
   downloads right after the first paint and the loader waits only if a part is still missing), or pre-downloading into the `rt.vfs` with priorities. Saves: up to ~270 MB of the 385 MB download on first paint and the same memory
   until parsed. Cost: medium; **risk:** `Environment` code may scan every part at `importModules` time (the private part holds the bodies that `Expr` fields of `ConstantInfo` point to, and the
   public part points *into* it), so the pointer graph between parts must be checked first (the loader already throws on a pointer into an unloaded part).
3. **Lazy decoding of `.olean` objects (not files).** Decode a region on demand per object instead of eagerly (shell objects with accessor properties, as in the earlier note). Saves: most of the 1.5 GB JS heap
   (~40-60%?) because a run touches a small fraction of `Init`'s constants. Cost: large, and slows every field access unless the accessors are hidden behind the existing `a0..` property names (getters on a prototype per
   class of object defeat V8's inline caches). Do (2) first: it removes the same bytes without touching the object model.
4. **Lazy initializers.** Today `--init-all` runs the `[init]`/`[builtin_init]` of every module (1.4 s, plus the heap they build: parser tables, attribute extensions, `registerBuiltinAttribute`...). Most of this is
   Lean's own `builtin_initialize` blocks that populate global tables the elaborator always needs, so laziness per *module* is limited; a per-*feature* split is possible (e.g. do not run the `Lean.Server.*`, `Lean.Linter.*`,
   `Lean.Widget.*` initializers for the `calc`/`elab` demos). Saves ~0.3-0.5 s and some MB. Cost: small if a module list is given at transpile time (`--init-only PREFIXES`), but the registered tables then lack those entries
   (must be consistent: skipped modules must not be imported by a later `importModules` either).
5. **Post-initialization snapshot.** Serialize the heap after `runInitializers` + `importModules Init` once (at build time, in Node), ship it, and deserialize in the page. This is the biggest possible win for start
   time (skips 1.4 s of initializers + the 8 s `importModules`, which is dominated by building the constants map and the extension states) but needs a serializer for closures and `IO.Ref`s (functions are code references,
   fine by name `rt.fn`), keeps all objects alive (no memory saving), and the snapshot is as large as the heap (~1 GB) unless the olean-backed objects stay references into the regions. Cost: large; fragile on every
   compiler change. Only worth it with (3).
6. **Code: split `elab.js` by module with lazy loading.** 174 MB of JS is compiled lazily by V8 (functions parsed on first call), so the memory cost is mostly the pre-parse and the source string (~200-300 MB). Splitting by module and
   `import()`-ing on demand needs asynchronous entry points; the main thread is synchronous. Prune instead: **`--eval-all` only for modules reachable from attribute/macro/parser registrations** (idea (4) of the earlier list). Saves
   maybe 30-40% of the JS (`Lean.Elab.Tactic.*`, `Lean.Meta.*` are needed; `Lean.Server.*`, `Lean.Compiler.IR.EmitC`, `Lake`-like parts are not). Cost: medium (needs a reachability analysis over IR, which exists as `--run`'s tree shaking).
7. **Cheaper objects.** Drop `n` and `rc: 0` for persistent olean objects, share `sbuf` in a prototype, use classes per constructor shape (V8 hidden classes already; gain ~15% of 1.5 GB). Cost: medium-large (code
   generator and runtime touch every object); low payoff compared to (2).

Recommendation (order of work if wanted): **(1) bundle + brotli (small, removes the fetch pool problem and gives progress), then (2) lazy download of `.olean.private`/`.ir`/`.server` (the biggest memory and download
saving per effort), then (6) pruning `--eval-all`**. Defer (3), (5), (7) until (2) is measured. Before any of this, a **measurement ticket** is cheap and tells what really is touched: log which regions/objects of each part are
dereferenced during `elab` and `demo` runs (expected: `.olean.private` < 10%).

*Question again (human), later:* which of (1), (2), (6) should be implemented (or only the measurement)? Not started; waits for the answer. Moving the item back to "TODO for humans" with the analysis as the pointer.

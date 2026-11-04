# Ticket: `lcnf-dump` command — dump LCNF of a Lean file as JSON

Status: **done** (implemented; see docs/design/lcnf-json.md)

## Goal

Add a command (new `lean_exe`, working name `lcnf-dump`) that takes a path to a
valid Lean 4 source file and writes the LCNF (Lean's compiler IR, "Lambda
Compiled Normal Form") of all declarations compiled from that file to stdout as
JSON. This is the first step of the pipeline: LCNF JSON is the input for the
later LCNF interpreter / LCNF-to-JavaScript transpiler (see README.md).

Usage target:

    lake exec lcnf-dump path/to/File.lean [--phase base|mono] [--out file.json]

## Background / pointers (verify against toolchain, Lean 4.35.0)

* LCNF lives in `Lean.Compiler.LCNF` (`Lean/Compiler/LCNF/*.lean` in the Lean
  source tree; `Basic.lean` defines `Decl`, `Code`, `LetValue`, `Arg`, `Param`,
  `LetDecl`, `FunDecl`, `Alt`, `Cases`, `LCtx`, etc.).
* Compiled decls are stored per phase in environment extensions
  (`baseExt`, `monoExt`); look for `getDeclAt?` / `getDeclCore?` /
  `Decl.saveBase` / `Decl.saveMono` in `Lean.Compiler.LCNF.PhaseExt`.
* The pass pipeline is in `Lean.Compiler.LCNF.Passes` / `PassManager`;
  `Lean.Compiler.LCNF.main`/`compile` runs it. Check whether the new code
  generator is enabled by default in 4.35 and which option (e.g.
  `compiler.enableNew`) controls it; the dump must not silently fall back to
  the old compiler.
* Quick manual look at the output: `set_option trace.Compiler.result true`
  in a Lean file prints final LCNF as text. The JSON dump should carry the
  same information.
* To process a file programmatically: use `Lean.Elab.runFrontend` (or
  `Lean.Elab.IO.processCommands`) to elaborate the file and obtain the final
  `Environment`, then enumerate the declarations added by this file (module
  data / `env.constants.map₂`, i.e. not imported ones) and fetch their LCNF
  from the extension. Need `Lean.initSearchPath (← Lean.findSysroot)` and
  `importModules` so that `import Lean`/`Init` resolve.

## Requirements

1. New executable target in `lakefile.toml` (e.g. `lcnf-dump`, root
   `LcnfDump.lean`), library code in `Lean2js/` (e.g. `Lean2js/LcnfJson.lean`)
   so it can be unit-tested.
2. `ToJson` (or hand-written) serializer for LCNF: `Decl` (name, levelParams,
   type, params, value/code, inline attrs, safe/recursive flags), `Code`
   (`let`, `fun`, `jp`, `jmp`, `cases`, `return`, `unreach`), `LetValue`
   (`value` literal, `erased`, `proj`, `const`, `fvar` app), `Param`, `Arg`
   (`erased`/`fvar`/`type`), literals (nat, str; later uint*), `Alt`
   (`alt` / `default`). Types may be serialized structurally or as a string; see
   open question 2.
3. Names: serialize `Name` as dotted string, or as array of components if
   components can be numeric/contain dots (see Q3). fvar ids must be stable
   within a decl (use the id's name as is, or renumber deterministically).
4. Output must be deterministic (sorted keys / declaration order as in the file)
   so that it can be used for golden-file tests.
5. Errors: elaboration errors in the input -> print messages to stderr, exit
   non-zero, no JSON on stdout.
6. Include a top-level `"version"` field for the schema, plus `"leanVersion"`
   (`Lean.versionString`) and `"phase"`.
7. Tests: a small set of `.lean` inputs under `tests/lcnf/` with expected
   `.json` goldens (a trivial function, pattern matching / `cases`, a
   recursive function, a structure with projections, a closure/lambda, string
   and Nat literals, a `partial def`, `IO` main). A script (`tests/run.sh` or a
   `lake test` driver) compares outputs.
8. Document the JSON schema in `docs/design/lcnf-json.md` and update
   README.md (per AGENTS.md).

## Out of scope

* Interpreting or transpiling the LCNF (separate tickets).
* Dumping code of imported modules (`Init`, `Std`); only decls defined in the
  input file. (Whole-program / transitive closure of reachable decls from
  imports is a likely follow-up ticket, since the JS backend will need
  `Init` functions too.)

## Questions (split out; recommended answers are implemented, revisable)

1. [Phase to dump](lcnf-002-question-phase.md) — default `mono`.
2. [Type representation](lcnf-003-question-types.md) — strings.
3. [Name encoding](lcnf-004-question-names.md) — dotted strings.
4. [Pretty vs compact](lcnf-005-question-json-format.md) — pretty by default.
5. [Auxiliary decls](lcnf-006-question-aux-decls.md) — include all.

## Done when

`lake exec lcnf-dump tests/lcnf/<case>.lean` outputs valid JSON matching the
goldens for all test cases, schema is documented in `docs/design/`, README is
updated, and this ticket is moved out of TODO.md's open lists.

# Tests for the infoview

Parent: [info-001](info-001-infoview-epic.md) | Status: **started** (2026-11-05): oracle + 9 cases done (see Result); still to add: interactive goals / hover / `getInteractiveDiagnostics` oracles and a larger corpus.
Oracle 1: drive native `lake env lean --server` with scripted LSP JSON-RPC (`initialize`, `didOpen`, `$/lean/plainGoal`, `$/lean/plainTermGoal`, `textDocument/hover`, `Lean.Widget.getInteractiveGoals`)
and store the responses as golden JSON (`tests/info/*.json`). Oracle 2: native calls of the same Lean functions (like the existing `tests/e2e` differential tests). The JS side must reproduce them byte for byte
for a corpus: proofs with several goals, `induction`/`cases` with case tags, `have`/`calc` blocks, incomplete prefixes (error recovery), term-mode holes, errors, `#eval` messages, unicode (UTF-16 columns).
Add the cases to `test.sh` (slow ones behind a flag, like `--quick` today).

## Result so far (2026-11-05)

* `tests/info/oracle.mjs` drives native `lean --server` (JSON-RPC over stdio, one fresh server per case — reusing one server for several documents returned `null` for some positions) for
  `$/lean/plainGoal` and `$/lean/plainTermGoal` at the positions of `tests/info/cases.json` (unfinished tactic proof, after/inside tactics, `induction … with` cases, `have`, term positions, `no goals`,
  unicode identifiers, error recovery). `tests/e2e/infocases.lean` prints `Lean2js.Info`'s answers in the same shape; `tests/info/compare.mjs` compares: **9 cases, 0 differences**.
  `tests/info/run.sh` does all that natively (part of `test.sh`); `tests/e2e/run.sh infocases` checks that the JS build prints exactly the same.
* To get identical goal *selection* `Lean2js.Info` uses the server's own logic on the command snapshot tree (`findCmd`, `findGoalsAt`, `findInfoTreeAtPos`, copied from the language server).

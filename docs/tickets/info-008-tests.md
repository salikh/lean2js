# Tests for the infoview

Parent: [info-001](info-001-infoview-epic.md) | Status: planned
Oracle 1: drive native `lake env lean --server` with scripted LSP JSON-RPC (`initialize`, `didOpen`, `$/lean/plainGoal`, `$/lean/plainTermGoal`, `textDocument/hover`, `Lean.Widget.getInteractiveGoals`)
and store the responses as golden JSON (`tests/info/*.json`). Oracle 2: native calls of the same Lean functions (like the existing `tests/e2e` differential tests). The JS side must reproduce them byte for byte
for a corpus: proofs with several goals, `induction`/`cases` with case tags, `have`/`calc` blocks, incomplete prefixes (error recovery), term-mode holes, errors, `#eval` messages, unicode (UTF-16 columns).
Add the cases to `test.sh` (slow ones behind a flag, like `--quick` today).

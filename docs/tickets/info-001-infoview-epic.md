# Epic: an "infoview" for the JS-hosted Lean (goals, messages, hover at a position)

Status: **planned — do not start before the remaining `self-*` tickets are done** (user instruction 2026-11-05: finish self-007 remainder,
[self-008](self-008-bundle-startup-size.md), [self-010](self-010-promise-drop-heuristic.md) first). This epic only collects the plan.

## Goal

Provide what the VS Code *Lean infoview* shows — the proof goals at the cursor, the messages (errors/warnings/`#eval` output) belonging to the
cursor, the expected type of a term, hover information (type, docstring, definition site) — from the Lean frontend that runs as JavaScript
([self-001](self-001-compiler-to-js-epic.md)). There is no editor sending LSP requests, so the interface must be **programmer friendly**:

* *prefix mode* — "I am writing a proof": send the text written so far (e.g. `theorem t : p ∧ q := by\n  constructor\n  `) and get the goals at its end;
* *cursor mode* — send a complete file/expression and a position inside it (line/column or offset) and get the info at that position.

Results are plain JSON (and a text rendering), reusable by a web UI and by tests.

## What exists in Lean (to reuse, not rewrite)

* `Lean.Elab.InfoTree` (collected while elaborating when `infoState.enabled`) with `InfoTree.goalsAt?`, `termGoalAt?`, `hoverableInfoAt?`
  (`Lean/Elab/InfoTree/Util.lean`), `Lean.Elab.Command.runCommandElabM`.
* The language-server request handlers (`Lean/Server/FileWorker/RequestHandling.lean`): `$/lean/plainGoal`, `$/lean/plainTermGoal`,
  `textDocument/hover`, `Lean.Widget.getInteractiveGoals` / `getInteractiveTermGoal` / `getInteractiveDiagnostics` (RPC with `RpcRef`s for
  sub-expression popups, `Lean.Widget.InteractiveCode`/`TaggedText`), documented in `Lean/Server/ProtocolOverview.lean`.
* `Lean.Language.Lean.process` (incremental snapshots) — already running in JS (self-009).
* A native reference oracle: `lean --server` can be driven with scripted LSP messages to record expected responses.

## Subtickets

* [info-002-question-architecture](info-002-question-architecture.md) — decided: thin layer over the InfoTree (the real `FileWorker` behind an in-memory LSP transport is *not* planned).
* [info-003-api-design](info-003-api-design.md) — the programmer-facing API: sessions, prefix mode, cursor mode, positions, JSON shapes.
* [info-004-infotree-goals](info-004-infotree-goals.md) — info trees + plain goals / term goals / messages at a position in the self-hosted frontend.
* [info-005-session-caching](info-005-session-caching.md) — a long-lived session (imported environment and snapshots cached; typing a character must not re-import `Init`).
* [info-006-interactive-hover](info-006-interactive-hover.md) — interactive goals (tagged sub-expressions), hover, go-to-definition, docstrings.
* [info-007-web-ui](info-007-web-ui.md) — the browser infoview next to an editor pane.
* [info-008-tests](info-008-tests.md) — differential tests against native Lean (`lean --server` transcripts and native calls of the same Lean functions).

## Order and dependencies

Prerequisites (must be finished first): self-007 (remaining primitives), self-008 (size/startup/memory — an infoview needs fast, repeated requests), self-010 (task
scheduler soundness — the server code relies on snapshot tasks and promises much more heavily than the batch frontend).
Then: 002 (decision) → 003 → 004 → 005 → 006 → 007, with 008 growing alongside.

## Done when

For a set of example proofs, the JSON for "goals at the end of the prefix" and "goals/hover at position P" is identical to what the native language server returns
(`$/lean/plainGoal`, `$/lean/plainTermGoal`, `textDocument/hover`, and the interactive goal structures), a web page shows them, and a typical request after the first one takes well under a second.

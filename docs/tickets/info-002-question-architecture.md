# Question: thin layer or the real FileWorker?

Parent: [info-001](info-001-infoview-epic.md)
Status: **decided 2026-11-05** — option A (thin layer over the InfoTree); the real FileWorker is not planned. No work starts before the self-* tickets are done.

Two ways to obtain infoview data in the JS-hosted frontend:

A. **Thin layer over the elaborator.** Run `Lean.Language.Lean.process`/`IO.processCommands` with info trees enabled, then call `InfoTree.goalsAt?`,
   `termGoalAt?`, `hoverableInfoAt?` and the pretty-printing helpers (`Lean.Meta.ppGoal`, `Lean.Widget.goalToInteractive`, …) ourselves; return JSON.
   Small, synchronous, easy to test, API exactly as we design it (info-003).
B. **The real language server.** Compile `Lean.Server.FileWorker` (and `Watchdog`?) to JS, feed it LSP messages through in-memory streams (`IO.FS.Stream.ofBuffer`-like),
   and expose a JSON-RPC interface (`didOpen`, `didChange`, `$/lean/plainGoal`, RPC calls). Maximal fidelity and future editor integration (Monaco + LSP),
   but needs threads/tasks/cancellation/RPC sessions to work in the cooperative scheduler, i.e. depends heavily on self-010.

**Recommended:** start with A (fast, no scheduler subtleties), structured so that the response shapes are the LSP shapes; add B afterwards as an alternative backend behind the same API
(info-003 keeps `goalsAt(request) → LSP-shaped JSON`), and use B-vs-native-server transcripts as the oracle in info-008.
Open sub-question: for B, run only the FileWorker (one file, no watchdog/file watching) — recommended yes.

## Answer

Stick with A.

## Update 2026-11-05

The user later asked for the actual LSP server in the demo: [demo-002](demo-002-lsp-infoview-in-demo.md) revisits this decision for a new demo page `lsp.html` (option B); `demo.html` is unchanged. Option A (`Lean2js/Info.lean`) stays as the programmer API / test oracle.

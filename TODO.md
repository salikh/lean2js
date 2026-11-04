# TODO

Keep this file as sections with simple bullet lists with
links to detailed tickets.

## TODO for humans

* [info-002-question-architecture](docs/tickets/info-002-question-architecture.md): thin layer over the InfoTree vs. the real FileWorker (recommended: thin layer first, FileWorker as a second backend) — not urgent, work starts after the self-* tickets

## Open tasks

* [tools-001-demo-and-test-scripts](docs/tickets/tools-001-demo-and-test-scripts.md): `demo.sh` and `test.sh` (done)

* [js-001-transpiler-epic](docs/tickets/js-001-transpiler-epic.md): Lean (IR) → JavaScript transpiler
  (epic; core done with the IR backend; mono backend removed; open: js-008…js-011, js-014, see ticket)
* [info-001-infoview-epic](docs/tickets/info-001-infoview-epic.md): infoview equivalent (goals/messages/hover at a position; prefix mode and cursor mode) — **planned, do not start before the remaining self-* tickets are done**
* [self-010-promise-drop-heuristic](docs/tickets/self-010-promise-drop-heuristic.md): investigate/confirm the "unresolved promise = dropped" scheduler heuristic (output of the self-hosted frontend may be wrong without error)
* [self-001-compiler-to-js-epic](docs/tickets/self-001-compiler-to-js-epic.md): compile the Lean compiler itself to JS
  (epic; **milestone reached 2026-11-05**: the frontend elaborates and `#eval`s in JS; open: self-008 size/startup gate, type-checking kernel, browser UI)

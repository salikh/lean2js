# TODO

Keep this file as sections with simple bullet lists with
links to detailed tickets.

## TODO for humans

* [self-008-bundle-startup-size](docs/tickets/self-008-bundle-startup-size.md): is more memory/startup optimization wanted? (recommended: no, the browser demos work at ≈ 2.6 GB / 42 s)
* [info-006-interactive-hover](docs/tickets/info-006-interactive-hover.md): representation of interactive goals / sub-expression popups (recommended: session object with integer ids + `infoPopup(id)`); everything else of info-006 is done
* [demo-002-lsp-infoview-in-demo](docs/tickets/demo-002-lsp-infoview-in-demo.md): the real `FileWorker` cannot run unmodified in the cooperative single-threaded runtime (needs coroutines). Use a protocol adapter over `Lean2js.Info` (recommended), or invest in a coroutine runtime?

## Open tasks

Done epics and tickets are listed in [docs/CHANGES.md](docs/CHANGES.md). What is left:

* [info-001-infoview-epic](docs/tickets/info-001-infoview-epic.md): infoview equivalent. Done: plain goals, term goals, messages, hover (identical to the real server on 15 oracle cases), sessions, a web page.
  Blocked on a human decision: interactive goals ([info-006](docs/tickets/info-006-interactive-hover.md)).
* [demo-002-lsp-infoview-in-demo](docs/tickets/demo-002-lsp-infoview-in-demo.md): `lsp.html` with an LSP server and a live infoview — blocked on a human decision (see above).
* [self-001-compiler-to-js-epic](docs/tickets/self-001-compiler-to-js-epic.md): the Lean compiler in JS — done (kernel, loader, initializers, browser build); further memory work ([self-008](docs/tickets/self-008-bundle-startup-size.md), ≈ 2.6 GB) waits for a human decision.
* [js-001-transpiler-epic](docs/tickets/js-001-transpiler-epic.md): Lean (IR) → JavaScript transpiler — done; the optional leftovers in [js-014](docs/tickets/js-014-cleanup-gaps.md) (`--bundle`, source maps) are not planned unless someone needs them.

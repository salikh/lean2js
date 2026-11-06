# Interactive goals, hover, go-to-definition

Parent: [info-001](info-001-infoview-epic.md) | Status: **hover done; interactive goals: decision made (session ids), not started**; hover (2026-11-05): `hover` in `Lean2js.Info` (the server's `handleHover`: info-tree hover with fallback to the docstring of the syntax kind) — identical to `textDocument/hover` of the real server on 6 cases (const, tactic keyword, local, type, command keyword, nothing), natively and in JS. **Open:** interactive goals (tagged sub-expressions + popups), go-to-definition.
`Lean.Widget.getInteractiveGoals` returns `InteractiveGoals` whose types are `CodeWithInfos` (`TaggedText` with `SubexprInfo` tags carrying `RpcRef`s); hovering a sub-expression calls
`InteractiveInfo`/`getInteractiveInfo` through the RPC session. Design a JSON form of tagged text and a stateless way to ask for the info of a sub-expression (path in the expression + request id)
instead of RPC references. Hover (`textDocument/hover`: type, docstring via `findDocString?`, module), go-to-definition (declaration ranges). Reuse the Lean-side widget code (it is transpiled for free).

## Question (human): representation of interactive goals — filed 2026-11-05

The real server answers `Lean.Widget.getInteractiveGoals` with `TaggedText`/`CodeWithInfos` whose sub-expressions carry `RpcRef`s (opaque handles into a server-side RPC session) used later by
`Lean.Widget.InteractiveDiagnostics`/`getGoToLocation`/`InteractiveInfo` popups. A stateless JSON API (info-003) cannot hand out server-side references.

Options: (1) **Recommended:** a stateful *session object* keeps the references (an integer id → `ExprWithCtx` map, cleared on the next request or after N requests) and the JSON contains those ids; the page calls
`infoPopup(id)` to get the hover info of a sub-expression (type, docstring, definition location); (2) stateless: encode the position of the sub-expression as a path (`Lean.SubExpr.Pos`) and recompute on demand from the
cursor request; (3) only plain text goals + hover (no sub-expression popups): already done.
Until answered I implement nothing for interactive goals; go-to-definition (location links) is independent and can follow `handleDefinition` directly.

Answer (human, 2026-11-06): let's go with (1).

## Decision recorded, plan (2026-11-06; not started)

Option (1), a stateful session object with integer ids, is chosen. Plan for the implementation (a future task, ready to start):
1. `Lean2js/Info.lean`: `interactiveGoalsAt` builds `Lean.Widget.InteractiveGoals` with the server's own `Lean.Widget.goalToInteractive` / `ppExprTagged` (transpiled for free); the `RpcRef`s inside the
   `CodeWithInfos` are replaced while serializing by integer ids `n` that index a table `Array ExprWithCtx`-like `SubexprInfo` held by the session (`IO.Ref`). The table is cleared by the next
   `interactiveGoalsAt` call (a bounded number of previous generations may be kept so that a stale popup still resolves).
2. `infoPopup(id)` export (`lean2js_session_info_popup`): returns `InteractiveInfo` (`Lean.Widget.InteractiveInfo`: type, expr, docstring through `findDocString?`) as JSON; unknown id -> `null`.
3. `driver.js`/`infoview.html`: render `TaggedText` (nested spans carrying ids), hover on a span calls `infoPopup(id)` and shows the tooltip.
4. Tests: extend `tests/info/` with cases comparing the *tagged text content* (flattened text must equal the plain goals already verified) and popups of the real server (`Lean.Widget.InteractiveDiagnostics`-style
   RPC via `lean --server` with `RpcRef`s is awkward to replay: compare by sub-expression text -> popup type string instead of by id). Go-to-definition (`handleDefinition`) stays independent.
Status: **decision made, implementation not started** (no longer in "TODO for humans"; listed under open tasks).

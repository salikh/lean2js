# Interactive goals, hover, go-to-definition

Parent: [info-001](info-001-infoview-epic.md) | Status: **hover done** (2026-11-05): `hover` in `Lean2js.Info` (the server's `handleHover`: info-tree hover with fallback to the docstring of the syntax kind) — identical to `textDocument/hover` of the real server on 6 cases (const, tactic keyword, local, type, command keyword, nothing), natively and in JS. **Open:** interactive goals (tagged sub-expressions + popups), go-to-definition.
`Lean.Widget.getInteractiveGoals` returns `InteractiveGoals` whose types are `CodeWithInfos` (`TaggedText` with `SubexprInfo` tags carrying `RpcRef`s); hovering a sub-expression calls
`InteractiveInfo`/`getInteractiveInfo` through the RPC session. Design a JSON form of tagged text and a stateless way to ask for the info of a sub-expression (path in the expression + request id)
instead of RPC references. Hover (`textDocument/hover`: type, docstring via `findDocString?`, module), go-to-definition (declaration ranges). Reuse the Lean-side widget code (it is transpiled for free).

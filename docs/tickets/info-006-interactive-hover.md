# Interactive goals, hover, go-to-definition

Parent: [info-001](info-001-infoview-epic.md) | Status: planned
`Lean.Widget.getInteractiveGoals` returns `InteractiveGoals` whose types are `CodeWithInfos` (`TaggedText` with `SubexprInfo` tags carrying `RpcRef`s); hovering a sub-expression calls
`InteractiveInfo`/`getInteractiveInfo` through the RPC session. Design a JSON form of tagged text and a stateless way to ask for the info of a sub-expression (path in the expression + request id)
instead of RPC references. Hover (`textDocument/hover`: type, docstring via `findDocString?`, module), go-to-definition (declaration ranges). Reuse the Lean-side widget code (it is transpiled for free).

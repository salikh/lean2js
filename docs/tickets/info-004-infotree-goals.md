# Info trees, goals and messages at a position

Parent: [info-001](info-001-infoview-epic.md) | Status: planned
Enable `infoState.enabled` in the self-hosted frontend (`Elab.Command` options / `Language.Lean.process` setup), keep the `InfoTree`s of all commands, and implement `goalsAt`, `termGoalAt`,
`messagesAt` (messages whose range contains the position, as the infoview shows them) with the same selection rules as `Lean.Server.FileWorker.RequestHandling.handlePlainGoal` /
`handlePlainTermGoal` (including the "goals after the cursor in a tactic block" rule via `GoalsAtResult.useAfter`). First as plain text (`Lean.Meta.ppGoal`), then structured. Tests: info-008.
Watch: the dropped-promise heuristic (self-010) — snapshot reporting and async elaboration; run with `Elab.async := false` initially.

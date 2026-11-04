# Programmer-friendly infoview API

Parent: [info-001](info-001-infoview-epic.md) | depends on the decision in [info-002](info-002-question-architecture.md)
Status: planned (design only)

Sketch (to be refined when work starts):

```js
const lean = await LeanSession.create({ imports: ["Init"] });          // cached environment (info-005)
// prefix mode: goals at the end of the text written so far
lean.infoAtEnd("theorem t (p q : Prop) (hp : p) (hq : q) : p ∧ q := by\n  constructor\n  ")
// cursor mode: position inside a complete text (0-based line/character as in LSP, or a UTF-8/UTF-16 offset)
lean.infoAt(source, { line: 3, character: 7 })
// results (JSON): { goals: [{ hyps: [{names, type, body?}], type, userName?, ctx... }], termGoal?: {...}, messages: [{range, severity, text}],
//                    hover?: { range, markdown }, plain: "text rendering as in the infoview" }
```
Requirements: emulate editing (the prefix may end in the middle of a tactic block — Lean's error recovery elaborates the incomplete proof with `sorry` and still produces goals);
positions in LSP conventions (UTF-16 code units, `Lean.FileMap`) plus byte-offset convenience; all outputs JSON-serializable; a text renderer for the CLI (`lean2js-info FILE --line L --col C`);
deterministic output for tests. Also decide: one call per kind of query (`goals`, `termGoal`, `hover`, `messages`) or one `info` call returning everything the infoview shows at that position.

import Lean
import Lean2js.Lsp
open Lean

/-- Like infocases.lean, but through the in-memory LSP server (Lean2js/Lsp.lean): initialize, didOpen, then
`$/lean/plainGoal`, `$/lean/plainTermGoal`, `textDocument/hover` requests. The output is compared with the real language server by tests/info/compare.mjs. -/
unsafe def main : IO Unit := do
  let cases ← IO.ofExcept (Json.parse (← IO.FS.readFile "tests/info/cases.json"))
  let mut out : Array Json := #[]
  let mut s ← Lean2js.Lsp.Server.new ()    -- one server (one `Init` import); each case re-opens the document
  let mut first := true
  for c in cases.getArr? |>.toOption |>.getD #[] do
    let source := c.getObjValAs? String "source" |>.toOption |>.getD ""
    let line := c.getObjValAs? Nat "line" |>.toOption |>.getD 0
    let ch := c.getObjValAs? Nat "character" |>.toOption |>.getD 0
    let send (s : Lean2js.Lsp.Server) (m : Json) : IO (Lean2js.Lsp.Server × Array Json) := do
      let (s, o) ← Lean2js.Lsp.handle s m.compress
      return (s, (← IO.ofExcept (Json.parse o)).getArr?.toOption.getD #[])
    let rpc := fun (id : Nat) (method : String) (params : Json) =>
      Json.mkObj [("jsonrpc", "2.0"), ("id", id), ("method", method), ("params", params)]
    let doc := Json.mkObj [("uri", "file:///t.lean"), ("languageId", "lean4"), ("version", 1), ("text", source)]
    if first then (s, _) ← send s (rpc 1 "initialize" (Json.mkObj []))
    first := false
    (s, _) ← send s (Json.mkObj [("jsonrpc", "2.0"), ("method", "textDocument/didOpen"), ("params", Json.mkObj [("textDocument", doc)])])
    let q := Json.mkObj [("textDocument", Json.mkObj [("uri", "file:///t.lean")]),
      ("position", Json.mkObj [("line", line), ("character", ch)])]
    let result := fun (os : Array Json) => os[0]?.bind (·.getObjVal? "result" |>.toOption) |>.getD Json.null
    let (s2, g) ← send s (rpc 2 "$/lean/plainGoal" q)
    let (s3, t) ← send s2 (rpc 3 "$/lean/plainTermGoal" q)
    let (s4, h) ← send s3 (rpc 4 "textDocument/hover" q)
    s := s4
    out := out.push <| Json.mkObj [("name", c.getObjValD "name"), ("goal", result g), ("termGoal", result t), ("hover", result h)]
  IO.println (Json.arr out).compress

import Lean
import Lean2js.Lsp
open Lean

/-- Protocol transcript of the in-memory LSP server: prints every response / notification (compared native vs. JS by the e2e runner). -/
unsafe def main : IO Unit := do
  let mut s ← Lean2js.Lsp.Server.new ()
  let msgs : List Json := [
    Json.mkObj [("jsonrpc", "2.0"), ("id", 1), ("method", "initialize"), ("params", Json.mkObj [])],
    Json.mkObj [("jsonrpc", "2.0"), ("method", "initialized"), ("params", Json.mkObj [])],
    Json.mkObj [("jsonrpc", "2.0"), ("method", "textDocument/didOpen"), ("params", Json.mkObj [("textDocument",
      Json.mkObj [("uri", "file:///a.lean"), ("version", 1), ("text", "def x : Nat := \"s\"\n#eval 1 + 1\n")])])],
    -- incremental change: replace the string literal by a number
    Json.mkObj [("jsonrpc", "2.0"), ("method", "textDocument/didChange"), ("params", Json.mkObj [
      ("textDocument", Json.mkObj [("uri", "file:///a.lean"), ("version", 2)]),
      ("contentChanges", Json.arr #[Json.mkObj [("range", Json.mkObj [("start", Json.mkObj [("line", 0), ("character", 15)]),
        ("end", Json.mkObj [("line", 0), ("character", 18)])]), ("text", "42")]])])],
    Json.mkObj [("jsonrpc", "2.0"), ("id", 2), ("method", "textDocument/hover"), ("params", Json.mkObj [
      ("textDocument", Json.mkObj [("uri", "file:///a.lean")]), ("position", Json.mkObj [("line", 0), ("character", 4)])])],
    -- full change
    Json.mkObj [("jsonrpc", "2.0"), ("method", "textDocument/didChange"), ("params", Json.mkObj [
      ("textDocument", Json.mkObj [("uri", "file:///a.lean"), ("version", 3)]),
      ("contentChanges", Json.arr #[Json.mkObj [("text", "example : 1 = 1 := by\n  rfl\n")]])])],
    Json.mkObj [("jsonrpc", "2.0"), ("id", 3), ("method", "$/lean/plainGoal"), ("params", Json.mkObj [
      ("textDocument", Json.mkObj [("uri", "file:///a.lean")]), ("position", Json.mkObj [("line", 1), ("character", 2)])])],
    Json.mkObj [("jsonrpc", "2.0"), ("id", 4), ("method", "textDocument/definition"), ("params", Json.mkObj [])],
    Json.mkObj [("jsonrpc", "2.0"), ("method", "$/unknown"), ("params", Json.mkObj [])],
    Json.mkObj [("jsonrpc", "2.0"), ("id", 5), ("method", "shutdown")],
    Json.mkObj [("jsonrpc", "2.0"), ("id", 6), ("method", "textDocument/hover"), ("params", Json.mkObj [])],
    Json.mkObj [("jsonrpc", "2.0"), ("method", "exit")]]
  for m in msgs do
    let (s', out) ← Lean2js.Lsp.handle s m.compress
    s := s'
    IO.println s!"> {m.compress}"
    IO.println s!"< {out}"

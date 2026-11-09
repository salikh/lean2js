import Lean
import Lean2js.Info
open Lean Elab

/-!
An in-memory LSP server for one document (ticket demo-002, option 1): speaks JSON-RPC messages (as strings, no `Content-Length` framing)
and answers with the *same Lean functions the language server uses* for goal selection, term goals and hover (`Lean2js.Info`).
Supported: `initialize`, `initialized`, `shutdown`, `exit`, `textDocument/didOpen|didChange|didClose` (full and incremental sync, the document
is elaborated on every change and `publishDiagnostics` is sent), `$/lean/plainGoal`, `$/lean/plainTermGoal`, `textDocument/hover`.
Unknown requests are answered with `MethodNotFound`, unknown notifications are ignored.
-/

namespace Lean2js.Lsp

structure Server where
  session : Session
  uri : String := ""
  version : Int := 0
  text : FileMap := "".toFileMap
  doc : Option Lean2js.Info.Elaborated := none
  shutdownRequested : Bool := false
  exited : Bool := false

@[export lean2js_lsp_new]
unsafe def Server.new (_unit : Unit) : IO Server :=
  return { session := ← Session.new () }

private def response (id : Json) (result : Json) : Json :=
  Json.mkObj [("jsonrpc", "2.0"), ("id", id), ("result", result)]

private def errorResponse (id : Json) (code : Int) (msg : String) : Json :=
  Json.mkObj [("jsonrpc", "2.0"), ("id", id), ("error", Json.mkObj [("code", code), ("message", msg)])]

private def notification (method : String) (params : Json) : Json :=
  Json.mkObj [("jsonrpc", "2.0"), ("method", method), ("params", params)]

private def capabilities : Json := Json.mkObj
  [("capabilities", Json.mkObj
      [("textDocumentSync", Json.mkObj [("openClose", true), ("change", (2 : Nat))]),   -- 2 = incremental
       ("hoverProvider", true)]),
   ("serverInfo", Json.mkObj [("name", "lean2js-lsp"), ("version", "0.1.0")])]

/-- Re-elaborates the document and returns the `publishDiagnostics` notification. -/
private def refresh (s : Server) : IO (Server × Array Json) := do
  let e ← Lean2js.Info.elaborate s.session s.text.source
  let diags ← e.diagnostics
  let note := notification "textDocument/publishDiagnostics"
    (Json.mkObj [("uri", s.uri), ("version", s.version), ("diagnostics", Json.arr diags)])
  return ({ s with doc := some e }, #[note])

private def posOf (params : Json) : Except String (Lsp.Position) := do
  let p ← params.getObjVal? "position"
  fromJson? p

private def uriOf (params : Json) : Except String String := do
  (← params.getObjVal? "textDocument").getObjValAs? String "uri"

/-- Handles a request on the current document. -/
private def handleRequest (s : Server) (method : String) (params : Json) : IO (Except (Int × String) Json) := do
  let ofExcept {α} (r : Except String α) : Except (Int × String) α := r.mapError ((-32602, ·))
  match method with
  | "initialize" => return .ok capabilities
  | "shutdown" => return .ok Json.null
  | "$/lean/plainGoal" | "$/lean/plainTermGoal" | "textDocument/hover" =>
    let some e := s.doc | return .ok Json.null
    match ofExcept (posOf params) with
    | .error err => return .error err
    | .ok lspPos =>
      let pos := s.text.lspPosToUtf8Pos lspPos
      match method with
      | "$/lean/plainGoal" =>
        match ← e.goals pos with
        | none => return .ok Json.null
        | some gs => return .ok <| Json.mkObj [("goals", toJson gs), ("rendered", Lean2js.Info.Elaborated.renderedGoals gs)]
      | "$/lean/plainTermGoal" => return .ok (← e.termGoal pos)
      | _ => return .ok (← e.hover pos)
  | _ => return .error (-32601, s!"method not found: {method}")

/-- Handles a notification; returns the new state and the notifications to send. -/
private def handleNotification (s : Server) (method : String) (params : Json) : IO (Server × Array Json) := do
  match method with
  | "exit" => return ({ s with exited := true }, #[])
  | "textDocument/didOpen" =>
    let td := params.getObjValD "textDocument"
    let some uri := (td.getObjValAs? String "uri").toOption | return (s, #[])
    let text := ((td.getObjValAs? String "text").toOption.getD "").crlfToLf
    refresh { s with uri, version := (td.getObjValAs? Int "version").toOption.getD 0, text := text.toFileMap }
  | "textDocument/didChange" =>
    let td := params.getObjValD "textDocument"
    let changes : Array Lsp.TextDocumentContentChangeEvent :=
      match (params.getObjValAs? (Array Lsp.TextDocumentContentChangeEvent) "contentChanges").toOption with
      | some c => c | none => #[]
    refresh { s with version := (td.getObjValAs? Int "version").toOption.getD (s.version + 1),
                     text := Lean.Server.foldDocumentChanges changes s.text }
  | "textDocument/didClose" =>
    return ({ s with doc := none, text := "".toFileMap },
      #[notification "textDocument/publishDiagnostics" (Json.mkObj [("uri", s.uri), ("diagnostics", Json.arr #[])])])
  | _ => return (s, #[])

/-- Handles one JSON-RPC message (a string); returns the new state and the messages to send, as a JSON array (string). -/
@[export lean2js_lsp_handle]
def handle (s : Server) (msg : String) : IO (Server × String) := do
  let out ← do
    match Json.parse msg with
    | .error err => pure (s, #[errorResponse Json.null (-32700) s!"parse error: {err}"])
    | .ok j =>
      let method? := (j.getObjValAs? String "method").toOption
      let params := j.getObjValD "params"
      let id? := (j.getObjVal? "id").toOption
      match method?, id? with
      | some m, some id =>                     -- request
        if s.shutdownRequested && m != "shutdown" then
          pure (s, #[errorResponse id (-32600) "server is shut down"])
        else
          let s := if m == "shutdown" then { s with shutdownRequested := true } else s
          match ← (handleRequest s m params) with
          | .ok r => pure (s, #[response id r])
          | .error (code, e) => pure (s, #[errorResponse id code e])
      | some m, none => handleNotification s m params   -- notification
      | none, _ => pure (s, #[])                 -- a response to a server request: ignored
  return (out.1, (Json.arr out.2).compress)

end Lean2js.Lsp

// A small LSP client for the in-memory server (Lean2js/Lsp.lean, run by driver.js): JSON-RPC requests/notifications, no transport —
// the server is synchronous, so a request returns its answer directly. Pages (lsp.html) use this; a stock LSP client could be attached
// through the same `send(message) → messages` function.
import { lspNew, lspSend } from "./driver.js";

export class LspClient {
  constructor({ uri = "file:///script.lean", onNotification = () => {} } = {}) {
    this.server = lspNew();
    this.uri = uri;
    this.version = 0;
    this.nextId = 1;
    this.onNotification = onNotification;
  }
  #dispatch(messages, id) {
    let result;
    for (const m of messages) {
      if (m.id !== undefined && m.id === id) { if (m.error) throw new Error(m.error.message); result = m.result; }
      else if (m.method) this.onNotification(m);
    }
    return result;
  }
  request(method, params) {
    const id = this.nextId++;
    return this.#dispatch(lspSend(this.server, { jsonrpc: "2.0", id, method, params }), id);
  }
  notify(method, params) { this.#dispatch(lspSend(this.server, { jsonrpc: "2.0", method, params })); }

  initialize() { const r = this.request("initialize", { capabilities: {} }); this.notify("initialized", {}); return r; }
  /** Opens (or replaces) the document; the diagnostics arrive through `onNotification`. */
  open(text) { this.notify("textDocument/didOpen", { textDocument: { uri: this.uri, languageId: "lean4", version: ++this.version, text } }); }
  /** Full-text change. */
  change(text) { this.notify("textDocument/didChange", { textDocument: { uri: this.uri, version: ++this.version }, contentChanges: [{ text }] }); }
  #at(method, position) { return this.request(method, { textDocument: { uri: this.uri }, position }); }
  plainGoal(position) { return this.#at("$/lean/plainGoal", position); }
  plainTermGoal(position) { return this.#at("$/lean/plainTermGoal", position); }
  hover(position) { return this.#at("textDocument/hover", position); }
}

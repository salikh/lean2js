// Loads the Lean library into the in-memory file system and runs the self-hosted Lean frontend (elab.js) on a source text.
// Used on the main thread (default; browsers give workers only ~40% of the stack, which the compiler's deep recursion exceeds)
// or inside a worker (worker.js, `?worker=1`).
import * as rt from "./lean_rt.js";

let program = null;

/** Downloads the library files into the runtime's in-memory file system and loads the compiler (once). */
export async function loadProgram({ files, root, onStatus }) {
  if (program !== null) return program;
  let n = 0, next = 0;
  const total = files.length;
  const pump = async () => {                       // a small pool: thousands of simultaneous fetches exhaust the browser
    while (next < total) {
      const f = files[next++];
      const r = await fetch(f.url);
      if (!r.ok) throw new Error(`${f.url}: ${r.status}`);
      rt.vfs.set(f.path, new Uint8Array(await r.arrayBuffer()));
      if (++n % 200 === 0) onStatus(`loaded ${n}/${total} library files`);
    }
  };
  await Promise.all(Array.from({ length: 12 }, pump));
  onStatus("loading the Lean frontend (a few seconds) …");
  await new Promise((r) => setTimeout(r, 20));      // let the page repaint
  globalThis.LEAN2JS_ENV = { LEAN_SYSROOT: root };
  program = await import("./elab.js");
  onStatus("initializing the Lean frontend …");
  await new Promise((r) => setTimeout(r, 20));
  rt.runInitializers();
  return program;
}

/** The runtime module, for hosts that need `vfs`, `setStdout`, … */
export { rt };

/** Calls an exported Lean IO function (`@[export lean2js_session_*]`); returns its value or throws the Lean error message. */
function callIO(name, ...args) {
  const r = rt.exports[name](...args, 0);
  if (r.t !== 0) throw new Error(rt.errorMessage(r.a0));
  return r.a0;
}
/** A persistent elaboration state (environment, namespaces, …): see Lean2js/Session.lean. */
export function newSession() { return { state: callIO("lean2js_session_new", 0) }; }
/** Elaborates `text` (commands) in the session; returns the messages as text. */
export function sessionRun(session, text, fileName = "<script>") {
  const r = callIO("lean2js_session_run", session.state, text, fileName);
  session.state = r.a0;
  return r.a1;
}
/** Evaluates a console line: a command as is, anything else with `#eval`. Returns the output text. */
export function sessionConsole(session, line) {
  const r = callIO("lean2js_session_console", session.state, line);
  session.state = r.a0;
  return r.a1;
}

/** Infoview query at an LSP position (0-based line, UTF-16 character) of `text`; returns the parsed JSON (see Lean2js/Info.lean). */
export function sessionInfo(session, text, line, character) {
  if (!session.state) throw new Error("no session");
  return JSON.parse(callIO("lean2js_session_info", session.state, text, line, character));
}
/** Prefix mode: the info at the end of `text` (the proof written so far). */
export function sessionInfoEnd(session, text) {
  return JSON.parse(callIO("lean2js_session_info_end", session.state, text));
}

/** A new in-memory LSP server (Lean2js/Lsp.lean; imports `Init`). */
export function lspNew() { return { state: callIO("lean2js_lsp_new", 0) }; }
/** Sends one JSON-RPC message (object) to the server; returns the array of messages it answers with (responses and notifications). */
export function lspSend(server, message) {
  const r = callIO("lean2js_lsp_handle", server.state, JSON.stringify(message));
  server.state = r.a0;
  return JSON.parse(r.a1);
}

export async function runSource({ files, root, source, onOut, onStatus }) {
  const program = await loadProgram({ files, root, onStatus });
  const lines = source.split("\n").map((l) => l + "\n");
  if (lines.at(-1) === "\n") lines.pop();
  rt.setStdout(onOut);
  rt.setStderr(onOut);
  rt.setStdinLine(() => lines.shift() ?? "");
  onStatus("elaborating (the page is unresponsive until this finishes) …");
  await new Promise((r) => setTimeout(r, 20));
  return rt.runMain(program.main, program.mainArity, []);
}

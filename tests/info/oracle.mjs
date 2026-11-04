// Oracle for the infoview tests (info-008): asks the native Lean language server (`lean --server`) for `$/lean/plainGoal` and
// `$/lean/plainTermGoal` at the positions of tests/info/cases.json. Prints JSON: [{name, goal, termGoal}]
// Usage: node tests/info/oracle.mjs > out/info.oracle.json
import { spawn } from "node:child_process";
import fs from "node:fs";
let cases = JSON.parse(fs.readFileSync(new URL("./cases.json", import.meta.url), "utf8"));
if (process.env.ONLY) cases = cases.filter((c) => c.name === process.env.ONLY);
async function runCase(c) {
const proc = spawn("lake", ["env", "lean", "--server"], { stdio: ["pipe", "pipe", "ignore"] });
let buf = Buffer.alloc(0);
const pending = new Map();
proc.stdout.on("data", (d) => {
  buf = Buffer.concat([buf, d]);
  for (;;) {
    const i = buf.indexOf("\r\n\r\n");
    if (i < 0) return;
    const m = /Content-Length: (\d+)/.exec(buf.subarray(0, i).toString());
    const len = Number(m[1]);
    if (buf.length < i + 4 + len) return;
    const msg = JSON.parse(buf.subarray(i + 4, i + 4 + len).toString("utf8"));
    buf = buf.subarray(i + 4 + len);
    if (msg.id !== undefined && pending.has(msg.id)) { pending.get(msg.id)(msg); pending.delete(msg.id); }
  }
});
const send = (o) => { const s = Buffer.from(JSON.stringify(o)); proc.stdin.write(`Content-Length: ${s.length}\r\n\r\n`); proc.stdin.write(s); };
let nextId = 1;
const request = (method, params) => new Promise((res) => { const id = nextId++; pending.set(id, res); send({ jsonrpc: "2.0", id, method, params }); });
await request("initialize", { processId: null, rootUri: null, capabilities: {} });
send({ jsonrpc: "2.0", method: "initialized", params: {} });
{
  const uri = `file:///case.lean`;
  send({ jsonrpc: "2.0", method: "textDocument/didOpen", params: { textDocument: { uri, languageId: "lean4", version: 1, text: c.source } } });
  const position = { line: c.line, character: c.character };
  const g = await request("$/lean/plainGoal", { textDocument: { uri }, position });
  const t = await request("$/lean/plainTermGoal", { textDocument: { uri }, position });
  proc.kill();
  return { name: c.name, goal: g.result ?? null, termGoal: t.result ?? null };
}
}
// a fresh server per case: a second document in the same server session was answered with null for some positions (races with elaboration)
const out = [];
for (const c of cases) out.push(await runCase(c));
console.log(JSON.stringify(out, null, 1));
process.exit(0);

// Times session/info requests of the JS-hosted frontend in Node (needs web/elab.js, built by web/build.sh selfhost).
// Usage: LEAN_SYSROOT=$(lean --print-prefix) node --stack-size=60000 selfhost/session-bench.mjs
import * as rt from "../web/lean_rt.js";
const t0 = performance.now();
const program = await import("../web/elab.js");
console.log(`load ${(performance.now() - t0).toFixed(0)} ms`);
rt.runInitializers();
console.log(`init ${(performance.now() - t0).toFixed(0)} ms`);
const io = (name, ...args) => { const r = rt.exports[name](...args, 0); if (r.t !== 0) throw new Error(rt.errorMessage(r.a0)); return r.a0; };
let t = performance.now();
let st = io("lean2js_session_new", 0);
console.log(`session.new ${(performance.now() - t).toFixed(0)} ms`);
const base = "theorem t (p q r : Prop) (hp : p) (hq : q) (hr : r) : p ∧ q ∧ r := by\n";
const steps = ["  constructor\n", "  · exact hp\n", "  constructor\n", "  · exact hq\n", "  · exact hr\n"];
let src = base;
for (const s of steps) {
  src += s;
  t = performance.now();
  const out = io("lean2js_session_info_end", st, src);
  const j = JSON.parse(out);
  console.log(`infoAtEnd after ${JSON.stringify(s.trim())}: ${(performance.now() - t).toFixed(0)} ms, ${j.goals.length} goal(s)`);
}

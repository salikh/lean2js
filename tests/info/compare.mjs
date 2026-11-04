// Compares the oracle (language server) with the output of Lean2js.Info: node tests/info/compare.mjs out/info.oracle.json out/infocases.expected
import fs from "node:fs";
const [oracleFile, oursFile] = process.argv.slice(2);
const oracle = JSON.parse(fs.readFileSync(oracleFile, "utf8"));
const ours = JSON.parse(fs.readFileSync(oursFile, "utf8"));
const norm = (x) => JSON.stringify(x, (k, v) => (v && typeof v === "object" && !Array.isArray(v) ? Object.fromEntries(Object.entries(v).sort()) : v));
let bad = 0;
for (let i = 0; i < oracle.length; i++) {
  const o = oracle[i], u = ours[i];
  const same = norm(o.goal) === norm(u.goal) && norm(o.termGoal) === norm(u.termGoal);
  if (same) console.log("ok: " + o.name);
  else { bad++; console.log("DIFF: " + o.name + "\n  server: " + norm({ goal: o.goal, termGoal: o.termGoal }) + "\n  ours:   " + norm({ goal: u.goal, termGoal: u.termGoal })); }
}
console.log(`${oracle.length} cases, ${bad} differences`);
process.exit(bad ? 1 : 0);

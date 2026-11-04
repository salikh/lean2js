// Lists runtime primitives referenced by generated JS files that runtime/lean_rt.js does not define.
// Usage: node tests/e2e/missing.mjs [FILE.js ...]     (default: out/*.js)
import * as rt from "../../runtime/lean_rt.js";
import fs from "node:fs";
const files = process.argv.length > 2 ? process.argv.slice(2)
  : fs.readdirSync("out").filter((f) => f.endsWith(".js") && !f.startsWith("lean_")).map((f) => "out/" + f);
const need = new Map();
for (const f of files) {
  const src = fs.readFileSync(f, "utf8");
  for (const m of src.matchAll(/rt\.prims\[("[^"]*")\]/g)) {
    const k = JSON.parse(m[1]);
    if (!(k in rt.prims)) need.set(k, (need.get(k) || []).concat(f));
  }
}
for (const [k, fs_] of [...need].sort()) console.log(k, "  <-", [...new Set(fs_)].slice(0, 3).join(","));
console.log(need.size, "missing");

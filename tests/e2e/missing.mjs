// Lists runtime primitives referenced by out/*.js that the corresponding runtime does not define.
import * as rtMono from "../../runtime/lean_runtime.js";
import * as rtIr from "../../runtime/lean_rt.js";
import fs from "node:fs";
const need = new Map();
for (const f of fs.readdirSync("out").filter((f) => f.endsWith(".js") && !f.startsWith("lean_"))) {
  const src = fs.readFileSync("out/" + f, "utf8");
  const rt = src.includes('"./lean_rt.js"') ? rtIr : rtMono;
  for (const m of src.matchAll(/^const e_\w+ = rt\.prims\[("[^"]*")\]/gm)) {
    const k = JSON.parse(m[1]);
    if (!(k in rt.prims)) need.set(k, (need.get(k) || []).concat(f));
  }
}
for (const [k, fs_] of [...need].sort()) console.log(k, "  <-", [...new Set(fs_)].slice(0, 3).join(","));
console.log(need.size, "missing");

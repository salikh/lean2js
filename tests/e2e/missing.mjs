// Lists runtime primitives referenced by out/*.js that lean_runtime.js does not define.
import * as rt from "../../runtime/lean_runtime.js";
import fs from "node:fs";
const need = new Map();
for (const f of fs.readdirSync("out").filter((f) => f.endsWith(".js") && f !== "lean_runtime.js")) {
  for (const m of fs.readFileSync("out/" + f, "utf8").matchAll(/^const e_\w+ = rt\.prims\[("[^"]*")\]/gm)) {
    const k = JSON.parse(m[1]);
    if (!(k in rt.prims)) need.set(k, (need.get(k) || []).concat(f));
  }
}
for (const [k, fs_] of [...need].sort()) console.log(k, "  <-", [...new Set(fs_)].slice(0, 3).join(","));
console.log(need.size, "missing");

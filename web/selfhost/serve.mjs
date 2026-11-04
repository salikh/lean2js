// Static file server for web/selfhost (python's http.server works too); `POST /report` appends the page's result to report.json
// (used by the headless-browser test). Usage: node web/selfhost/serve.mjs [port]
import http from "node:http";
import fs from "node:fs";
import path from "node:path";
const root = path.dirname(new URL(import.meta.url).pathname);
const port = Number(process.argv[2] ?? 8000);
const types = { ".html": "text/html", ".js": "text/javascript", ".json": "application/json", ".olean": "application/octet-stream" };
http.createServer((req, res) => {
  if (req.method === "POST" && req.url === "/report") {
    let body = ""; req.on("data", (d) => (body += d)); req.on("end", () => { fs.writeFileSync(path.join(root, "report.json"), body); res.end("ok"); });
    return;
  }
  const url = new URL(req.url, "http://x");
  const file = path.join(root, decodeURIComponent(url.pathname === "/" ? "/index.html" : url.pathname));
  if (!file.startsWith(root) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) { res.statusCode = 404; return res.end("not found"); }
  res.setHeader("Content-Type", types[path.extname(file)] ?? "application/octet-stream");
  res.setHeader("Content-Length", fs.statSync(file).size);
  fs.createReadStream(file).pipe(res);
}).listen(port, () => console.log(`http://localhost:${port}/`));

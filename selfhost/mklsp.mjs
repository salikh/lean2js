// Frames JSON-RPC messages (stdin: one JSON object per line) with Content-Length headers; prints to stdout.
import fs from "node:fs";
for (const line of fs.readFileSync(0, "utf8").split("\n").filter((l) => l.trim())) {
  const body = Buffer.from(JSON.stringify(JSON.parse(line)));
  process.stdout.write(`Content-Length: ${body.length}\r\n\r\n`);
  process.stdout.write(body);
}

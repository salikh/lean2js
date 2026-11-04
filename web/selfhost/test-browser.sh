#!/bin/sh
# Runs the default program of web/selfhost/index.html in headless Chrome (needs `web/selfhost/build.sh` first) and compares its output
# with the expected output. Starts a local server and a private Chrome instance and closes both (through the DevTools protocol / its pid).
# Usage: web/selfhost/test-browser.sh [chrome-binary]        (takes about a minute)
cd "$(dirname "$0")" || exit 1
chrome=${1:-google-chrome}
port=8731; dbg=9731
rm -f report.json
node serve.mjs $port > /dev/null 2>&1 & server=$!
prof=$(mktemp -d)
"$chrome" --headless=new --no-sandbox --disable-gpu --user-data-dir="$prof" --remote-debugging-port=$dbg "http://localhost:$port/index.html?autorun&report" > /dev/null 2>&1 &
i=0
while [ ! -s report.json ] && [ $i -lt 300 ]; do sleep 2; i=$((i + 1)); done
node -e '(async()=>{try{const v=await (await fetch("http://localhost:'$dbg'/json/version")).json();const ws=new WebSocket(v.webSocketDebuggerUrl);ws.onopen=()=>ws.send(JSON.stringify({id:1,method:"Browser.close"}));ws.onclose=()=>process.exit(0);setTimeout(()=>process.exit(0),5000)}catch(e){}})()'
kill $server 2>/dev/null
rm -rf "$prof"
[ -s report.json ] || { echo "FAIL: no report from the browser"; exit 1; }
node -e '
const r = JSON.parse(require("fs").readFileSync("report.json", "utf8"));
const expected = "6765\nNat.add_comm : ∀ (n m : Nat), n + m = m + n\n{ x := 1, y := 2 }\n";
if (r.code === 0 && r.out === expected) { console.log("ok: browser output matches (" + r.seconds.toFixed(0) + " s)"); }
else { console.log("FAIL: exit " + r.code + "\n" + r.out); process.exit(1); }'

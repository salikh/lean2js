#!/bin/sh
# Runs the pages of web/selfhost in headless Chrome (needs `web/selfhost/build.sh` first) and compares what they print with the expected output:
#   1. index.html (the editor page): its default program,
#   2. demo.html (script + data.json + console): runs the stats script, evaluates some console lines.
# Starts a local server and a private Chrome instance per page and closes them (through the DevTools protocol / pid).
# Usage: web/selfhost/test-browser.sh [chrome-binary]        (takes about 1.5 minutes)
cd "$(dirname "$0")" || exit 1
chrome=${1:-google-chrome}
port=8731; dbg=9731
status=0

# page_test NAME 'URL query' EXPECTED_FILE
page_test() {
  rm -f report.json
  node serve.mjs $port > /dev/null 2>&1 & server=$!
  prof=$(mktemp -d)
  "$chrome" --headless=new --no-sandbox --disable-gpu --user-data-dir="$prof" --remote-debugging-port=$dbg "http://localhost:$port/$2" > /dev/null 2>&1 &
  i=0
  while [ ! -s report.json ] && [ $i -lt 300 ]; do sleep 2; i=$((i + 1)); done
  node -e '(async()=>{try{const v=await (await fetch("http://localhost:'$dbg'/json/version")).json();const ws=new WebSocket(v.webSocketDebuggerUrl);ws.onopen=()=>ws.send(JSON.stringify({id:1,method:"Browser.close"}));ws.onclose=()=>process.exit(0);setTimeout(()=>process.exit(0),5000)}catch(e){}})()'
  kill $server 2>/dev/null
  sleep 1; rm -rf "$prof" 2>/dev/null
  [ -s report.json ] || { echo "FAIL ($1): no report from the browser"; status=1; return; }
  node -e '
    const fs = require("fs");
    const r = JSON.parse(fs.readFileSync("report.json", "utf8"));
    const expected = fs.readFileSync(process.argv[1], "utf8");
    if (r.code === 0 && r.out === expected) console.log("ok: " + process.argv[2] + " (" + r.seconds.toFixed(0) + " s)");
    else { console.log("FAIL: " + process.argv[2] + " (exit " + r.code + ")\n--- got\n" + r.out + "--- expected\n" + expected); process.exit(1); }' "$3" "$1" || status=1
}

page_test index 'index.html?autorun&report' expected/index.txt
page_test demo 'demo.html?autorun&report&console=main&console=mean%20%23%5B1.0%2C%202.0%2C%206.0%5D&console=def%20twice%20(x%20%3A%20Nat)%20%3A%3D%202%20*%20x&console=twice%2021&console=nosuchname' expected/demo.txt
exit $status

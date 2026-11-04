#!/bin/sh
# Builds the browser version of the self-hosted Lean frontend into web/selfhost/:
#   elab.js (the compiler, ~170 MB), the runtime, files.json (the .olean files of Init to download), copies of the library files.
# Usage: web/selfhost/build.sh      then:  python3 -m http.server -d web/selfhost 8000   and open http://localhost:8000/
cd "$(dirname "$0")/../.." || exit 1
out=web/selfhost
lake exe lean2js selfhost/Elab.lean --init-all --eval-all --small --out $out/elab.js || exit 1   # no --run: the worker calls main
cp runtime/*.js $out/
prefix=$(lake env lean --print-prefix)
rm -rf $out/lib && mkdir -p $out/lib
# all library files of the `Init` package (what `import Init` reads: .olean, .olean.server, .olean.private, .ir, .ir.sig)
(cd "$prefix/lib/lean" && find Init Init.* -type f \( -name '*.olean*' -o -name '*.ir' -o -name '*.ir.sig' \) 2>/dev/null) | sort -u > $out/filelist.txt
while read -r f; do mkdir -p "$out/lib/$(dirname "$f")"; cp "$prefix/lib/lean/$f" "$out/lib/$f"; done < $out/filelist.txt
node -e '
const fs=require("fs"); const list=fs.readFileSync(process.argv[1],"utf8").trim().split("\n");
const files=list.map(f=>({url:"lib/"+f, path:"/lean/lib/lean/"+f}));
fs.writeFileSync(process.argv[2], JSON.stringify({root:"/lean", files}));
console.log(files.length+" library files");' $out/filelist.txt $out/files.json

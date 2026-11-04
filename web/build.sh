#!/bin/sh
# Builds the generated files of the web demos into web/ (all of them are git-ignored):
#   web/build.sh calc        calc.html:   transpiles web/examples/calc.lean (a program with stdin) → prog.js, prog.lean, prog.stdin
#   web/build.sh selfhost    elab.html, demo.html, infoview.html: the Lean frontend as JavaScript (elab.js, ~170 MB) and the library files
#                            of `Init` (lib/, files.json, ~160 MB)
#   web/build.sh             both
#   web/build.sh PROGRAM.lean   like `calc`, for another program that reads stdin (prefilled from PROGRAM.stdin if it exists)
# Then serve web/ over HTTP and open http://localhost:8000/ :
#   node web/serve.mjs 8000      (or: python3 -m http.server -d web 8000)
cd "$(dirname "$0")/.." || exit 1

build_calc() {
  src=${1:-web/examples/calc.lean}
  lake exe lean2js "$src" --out web/prog.js || exit 1
  cp runtime/*.js web/
  cp "$src" web/prog.lean
  if [ -f "${src%.lean}.stdin" ]; then cp "${src%.lean}.stdin" web/prog.stdin; else : > web/prog.stdin; fi
}

build_selfhost() {
  out=web
  # no --run: the pages call `main` / the session exports themselves
  lake exe lean2js selfhost/Elab.lean --init-all --eval-all --small --out $out/elab.js || exit 1
  cp runtime/*.js $out/
  prefix=$(lake env lean --print-prefix)
  rm -rf $out/lib && mkdir -p $out/lib
  # all library files of the `Init` package (what `import Init` reads: .olean, .olean.server, .olean.private, .ir, .ir.sig)
  (cd "$prefix/lib/lean" && find Init Init.* -type f \( -name '*.olean*' -o -name '*.ir' -o -name '*.ir.sig' \) 2>/dev/null) | sort -u > $out/filelist.txt
  while read -r f; do mkdir -p "$out/lib/$(dirname "$f")"; cp "$prefix/lib/lean/$f" "$out/lib/$f"; done < $out/filelist.txt
  node -e '
    const fs = require("fs"); const list = fs.readFileSync(process.argv[1], "utf8").trim().split("\n");
    const files = list.map((f) => ({ url: "lib/" + f, path: "/lean/lib/lean/" + f }));
    fs.writeFileSync(process.argv[2], JSON.stringify({ root: "/lean", files }));
    console.log(files.length + " library files");' $out/filelist.txt $out/files.json
}

case "$1" in
  "" | all) build_calc; build_selfhost ;;
  calc) build_calc ;;
  selfhost) build_selfhost ;;
  *.lean) build_calc "$1" ;;
  *) echo "usage: $0 [calc|selfhost|all|PROGRAM.lean]"; exit 2 ;;
esac

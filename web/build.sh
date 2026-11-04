#!/bin/sh
# Usage: web/build.sh PROGRAM.lean   -- transpiles into web/prog.js, copies the runtime, the source (prog.lean) and the
# sample input PROGRAM.stdin (if present, prefilled in the page); then serve web/ over HTTP:
#   python3 -m http.server -d web 8000
# Example: web/build.sh web/examples/calc.lean
cd "$(dirname "$0")/.." || exit 1
src="$1"
lake exe lean2js "$src" --out web/prog.js || exit 1
cp runtime/lean_rt.js web/
cp "$src" web/prog.lean
if [ -f "${src%.lean}.stdin" ]; then cp "${src%.lean}.stdin" web/prog.stdin; else : > web/prog.stdin; fi

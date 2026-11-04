#!/bin/sh
# Usage: web/build.sh PROGRAM.lean   -- transpiles into web/prog.js and copies the runtime; then serve web/ over HTTP:
#   python3 -m http.server -d web 8000
cd "$(dirname "$0")/.." || exit 1
lake exe lean2js "$1" --out web/prog.js && cp runtime/lean_runtime.js web/

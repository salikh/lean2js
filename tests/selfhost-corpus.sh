#!/bin/sh
# Corpus check for the self-hosted frontend (self-010): elaborate many existing .lean files with the frontend running as JavaScript
# (strict task mode: an unresolved promise is an error, not a guess) and with the native frontend, and compare the messages.
# Usage: tests/selfhost-corpus.sh [FILE.lean ...]     (default: demo/*.lean and the e2e programs that do not import Lean/Std)
# Needs: lake exe lean2js selfhost/Elab.lean --init-all --eval-all --small --run --out out/selfhost_small.js   (done by tests/e2e/run.sh selfhost)
cd "$(dirname "$0")/.." || exit 1
export LEAN_SYSROOT=$(lake env lean --print-prefix)
[ -f out/selfhost_small.js ] || { echo "build out/selfhost_small.js first (see header)"; exit 2; }
files="$*"
if [ -z "$files" ]; then
  files=$(ls demo/*.lean web/selfhost/examples/*.lean; grep -L "^import" tests/e2e/*.lean)
fi
fail=0; n=0
for f in $files; do
  n=$((n + 1))
  # drop `main`-driven programs' effects: only the messages of elaboration matter, both sides run the same Elab.lean
  lake env lean --run selfhost/Elab.lean < "$f" > out/corpus.native 2>&1
  LEAN2JS_STRICT_TASKS=1 LEAN2JS_TIMING=1 node out/selfhost_small.js < "$f" > out/corpus.js 2> out/corpus.js.err
  guesses=$(grep -o "dropped-promise guesses: [0-9]*" out/corpus.js.err | tail -1)
  if cmp -s out/corpus.native out/corpus.js; then echo "ok: $f ($guesses)"; else echo "DIFF: $f ($guesses)"; diff out/corpus.native out/corpus.js | head -5; fail=$((fail + 1)); fi
done
echo "$n files, $fail differences"
[ $fail -eq 0 ]

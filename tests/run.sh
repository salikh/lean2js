#!/bin/sh
# Golden tests for lcnf-dump. Usage: tests/run.sh [--update]
# For each tests/lcnf/NAME.lean compares `lcnf-dump` output (mono phase, pretty)
# with tests/lcnf/NAME.mono.json.
cd "$(dirname "$0")/.." || exit 1
lake build lcnf-dump >/dev/null 2>&1 || { echo "build failed"; exit 1; }
fail=0
for src in tests/lcnf/*.lean; do
  golden="${src%.lean}.mono.json"
  actual=$(lake exe lcnf-dump "$src" --phase mono 2>/dev/null) || { echo "FAIL (dump error): $src"; fail=1; continue; }
  if [ "$1" = "--update" ]; then
    printf '%s\n' "$actual" > "$golden"; echo "updated $golden"
  elif [ "$actual" = "$(cat "$golden" 2>/dev/null)" ]; then
    echo "ok: $src"
  else
    echo "FAIL: $src (differs from $golden)"; fail=1
  fi
  # output must be valid JSON
  printf '%s\n' "$actual" | python3 -c 'import json,sys; json.load(sys.stdin)' || { echo "FAIL (invalid JSON): $src"; fail=1; }
done
# elaboration errors: non-zero exit, empty stdout
bad=$(mktemp --suffix=.lean); echo 'def x : Nat := "a"' > "$bad"
out=$(lake exe lcnf-dump "$bad" 2>/dev/null); rc=$?
rm -f "$bad"
if [ $rc -ne 0 ] && [ -z "$out" ]; then echo "ok: error case"; else echo "FAIL: error case (rc=$rc)"; fail=1; fi
exit $fail

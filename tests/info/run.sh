#!/bin/sh
# Infoview tests (info-008): the native language server (`lean --server`) is the oracle for `$/lean/plainGoal` / `$/lean/plainTermGoal`;
# the natively run Lean2js.Info must agree with it on tests/info/cases.json (the JS build is compared with native by tests/e2e/infocases.lean).
cd "$(dirname "$0")/../.." || exit 1
export LEAN_SYSROOT=$(lake env lean --print-prefix)
mkdir -p out
lake build Lean2js.Info > /dev/null 2>&1 || { echo "build failed"; exit 1; }
timeout 600 node tests/info/oracle.mjs > out/info.oracle.json || { echo "oracle failed"; exit 1; }
lake env lean --run tests/e2e/infocases.lean > out/infocases.native 2>&1 < /dev/null || { echo "infocases failed"; exit 1; }
node tests/info/compare.mjs out/info.oracle.json out/infocases.native || exit 1
# the in-memory LSP server (Lean2js.Lsp, demo-002) must agree with the oracle too, answering through real JSON-RPC messages
lake env lean --run tests/e2e/lspcases.lean > out/lspcases.native 2>&1 < /dev/null || { echo "lspcases failed"; exit 1; }
node tests/info/compare.mjs out/info.oracle.json out/lspcases.native

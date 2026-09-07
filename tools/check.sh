#!/usr/bin/env bash
# check.sh — zebra-ide's gate. Runs from the repo root. Needs `zebra` on PATH (or ZEBRA=).
#   1. sci_test          constants module loads (headless)
#   2. buffers_test      document bookkeeping (headless)
#   3. gates_test        manifest + runner vs the real compiler (headless)
#   4. dap_client_test   DAP client vs real `zebra debug` + lldb-dap — SKIP (not PASS)
#                        when lldb-dap is absent
#   5. lsp_client_test   client vs a real `zebra lsp` (headless)
#   6. ide.zbr on tui    compile control for the app (no native widgets needed)
#   7. libui sema        `zig build-obj` for x86_64-windows against zig-libui-ng bindings
#                        (LIBUI_BINDINGS=<zig-libui-ng/src>; skipped if absent)
#   8. gates runner      the CLI on this repo's own manifest
# Exit 0 requires every step PASS or SKIP; a SKIP is printed as SKIP, never as PASS.
set -u
cd "$(dirname "$0")/.."
ZEBRA=${ZEBRA:-zebra}
fail=0
step() { echo "── $1"; }
step "sci_test";        (cd src && "$ZEBRA" sci_test.zbr 2>&1 | tail -1 | grep -q "sci_test: ok") && echo PASS || { echo FAIL; fail=1; }
step "buffers_test";    (cd src && "$ZEBRA" buffers_test.zbr 2>&1 | tail -1 | grep -q "buffers_test: ok") && echo PASS || { echo FAIL; fail=1; }
step "gates_test";      (cd src && "$ZEBRA" gates_test.zbr 2>&1 | tail -1 | grep -q "gates_test: ok") && echo PASS || { echo FAIL; fail=1; }
step "dap_client_test"
dap_out=$(cd src && "$ZEBRA" dap_client_test.zbr 2>&1 | tail -1)
case "$dap_out" in
  *"dap_client_test: ok"*) echo PASS ;;
  *"dap_client_test: skipped"*) echo "SKIP (lldb-dap not on PATH — the debugger was NOT exercised)" ;;
  *) echo FAIL; fail=1 ;;
esac
step "lsp_client_test"; (cd src && "$ZEBRA" lsp_client_test.zbr 2>&1 | tail -1 | grep -q "lsp_client_test: ok") && echo PASS || { echo FAIL; fail=1; }
step "ide.zbr (tui, compile only)"
(cd src && rm -rf ide_gui_tui && "$ZEBRA" -c --check-full --gui-backend=tui ide.zbr >/dev/null 2>&1; [ -f ide_gui_tui/zig-out/bin/app ] || [ -f ide_gui_tui/zig-out/bin/app.exe ]) && echo PASS || { echo FAIL; fail=1; }
B=${LIBUI_BINDINGS:-}
if [ -z "$B" ]; then for c in /home/claude/libui-bindings /c/Projects/zig-libui-ng/src; do [ -f "$c/ui.zig" ] && B=$c; done; fi
if [ -n "$B" ]; then
  step "ide.zbr (libui_ng, sema vs $B)"
  (cd src && rm -rf ide_gui_libui_ng && "$ZEBRA" --gui-backend=libui_ng ide.zbr >/dev/null 2>&1; cd ide_gui_libui_ng && zig build-obj -target x86_64-windows-gnu -fno-emit-bin --dep ui --dep sci -Mroot=src/main.zig --dep ui -Msci="$B/sci.zig" -Mui="$B/ui.zig") && echo PASS || { echo FAIL; fail=1; }
else
  step "libui sema: skipped (set LIBUI_BINDINGS)"
fi
step "gates runner on this project's manifest (headless CLI)"
# `zebra` must be on PATH for the manifest's commands; use the same binary as $ZEBRA
(cd src && PATH="$(dirname "$(readlink -f "$ZEBRA")"):$PATH" "$ZEBRA" gates.zbr -- ../zebra-ide.json sci_test buffers_test 2>&1 | tail -3 | grep -q "2/2 gates passed") && echo PASS || { echo FAIL; fail=1; }
rm -f src/*.zig
exit $fail

#!/usr/bin/env bash
# check.sh — zebra-ide's gate. Runs from the repo root. Needs `zebra` on PATH (or ZEBRA=).
#   1. sci_test          constants module loads (headless)
#   2. buffers_test      document bookkeeping (headless)
#   3. textops_test      applyEdits / symbolLines / auto-indent, pure (headless)
#   3'. ignore_test      the explorer's .gitignore filter: glob, anchoring, dir-only,
#                        negation, and this repo's own .gitignore both ways (pure)
#   3a. keys_test        the shortcut table: no duplicate chords, Scintilla's own keys unclaimed
#   3b. gates_test       manifest + runner vs the real compiler (headless)
#   3b'. tests_test      the test runner vs the real compiler: `zebra test --list`
#                        discovery, pass / raising fail / panicking crash / not-run
#                        statuses and jump lines, a `--only` re-run (headless)
#   3b'''. icons_test     the toolbar glyphs' byte arithmetic (headless)
#   3b''. coverage_test  coverage.zbr against a literal zebra-coverage.json: counts, the
#                        denominator, sorting, base-name matching, the pane rows (pure)
#   3c. tools_test       process plugins: manifest `tools`, ${file}/${word} substitution, a real
#                        `zig fmt` reformat, a diagnostic-emitting tool, an on:save hook
#   3d. model_test       the IDE's Model driven headless on the tui backend: save-before-run,
#                        reload only after exit 0, no-diags tools never mark, per-run bookkeeping
#                        with two queued runs, the on:save hook through the queue (refuter's ask)
#                        + Run tests with coverage: the --coverage run, the JSON loaded, the
#                        untaken arm named as the first uncovered line (09-23)
#   4. dap_client_test   DAP client vs real `zebra debug` + lldb-dap — SKIP (not PASS)
#                        when lldb-dap is absent
#   5. lsp_client_test   client vs a real `zebra lsp` (headless)
#   5b. rename_workspace_test  the multi-file rename loop end to end: two files, one open,
#                        in-memory + on-disk halves, then the renamed program still runs
#                        (headless; found BUG-352/353 and the open-docs-only server on 09-08)
#   5c. cross_lsp_test   the same client against clangd (C) and zls (Zig): diagnostics on a
#                        broken edit, definition, references, rename — SKIP (not PASS) when a
#                        server is not on PATH
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
# expect PATTERN MODE CMD...: run CMD in src/, PASS if its output matches PATTERN (MODE
# `last` = the last line, `any` = anywhere). On FAIL, print the output's tail: a bare FAIL
# was all CI showed the first time lsp_client_test failed on Linux, and the log it needed
# had been thrown away by `| tail -1 | grep -q`.
expect() {
  local pat="$1" mode="$2"; shift 2
  local out; out=$(cd src && "$@" 2>&1)
  local hay="$out"; [ "$mode" = last ] && hay=$(printf '%s\n' "$out" | tail -1)
  if printf '%s\n' "$hay" | grep -q -- "$pat"; then echo PASS; return 0; fi
  echo FAIL; printf '%s\n' "$out" | tail -15 | sed 's/^/    | /'; fail=1; return 1
}
step "sci_test";        expect "sci_test: ok" last "$ZEBRA" sci_test.zbr
step "buffers_test";    expect "buffers_test: ok" last "$ZEBRA" buffers_test.zbr
step "textops_test";    expect "textops_test: ok" last "$ZEBRA" textops_test.zbr
step "ignore_test";     expect "ignore_test: ok" last "$ZEBRA" ignore_test.zbr
# keys.zbr names CodeEditor (registerShortcuts, the BUG-355 witness), so it needs a GUI
# backend — on tui the stub. Refuter, 09-08: run headless it did not even compile.
step "keys_test (tui)"; rm -rf src/keys_test_gui_tui; expect "keys_test: ok" last "$ZEBRA" --gui-backend=tui keys_test.zbr
step "gates_test";      expect "gates_test: ok" last "$ZEBRA" gates_test.zbr
step "tests_test";      rm -rf src/tests_tmp; expect "tests_test: ok" last "$ZEBRA" tests_test.zbr
step "tools_test";      expect "tools_test: ok" last "$ZEBRA" tools_test.zbr
# coverage.zbr (09-23): the compiler's zebra-coverage.json read for the Coverage pane --
# arithmetic, sorting, base-name matching and the rows, against a literal file (pure)
step "coverage_test (zebra test)"; expect "^4 passed, 0 failed" any "$ZEBRA" test coverage_test.zbr
# icons.zbr (09-23): the toolbar glyphs -> RGBA bytes, pure
step "icons_test (zebra test)"; expect "^3 passed, 0 failed" any "$ZEBRA" test icons_test.zbr
step "model_test (tui, headless Model)"; rm -rf src/model_test_gui_tui; expect "model_test: ok" last "$ZEBRA" --gui-backend=tui model_test.zbr
step "dap_client_test"
dap_out=$(cd src && "$ZEBRA" dap_client_test.zbr 2>&1 | tail -1)
case "$dap_out" in
  *"dap_client_test: ok"*) echo PASS ;;
  *"dap_client_test: skipped"*) echo "SKIP (lldb-dap not on PATH — the debugger was NOT exercised)" ;;
  *) echo FAIL; fail=1 ;;
esac
step "lsp_client_test"; expect "lsp_client_test: ok" last "$ZEBRA" lsp_client_test.zbr
step "rename_workspace_test"; expect "rename_workspace_test: ok" last "$ZEBRA" rename_workspace_test.zbr
step "cross_lsp_test (clangd + zls)"
cross_out=$(cd src && "$ZEBRA" cross_lsp_test.zbr 2>&1 | tail -1)
case "$cross_out" in
  *"cross_lsp_test: ok"*) echo PASS ;;
  *"cross_lsp_test: skipped"*) echo "SKIP ($cross_out)" ;;
  *) echo "FAIL ($cross_out)"; fail=1 ;;
esac
step "ide.zbr (tui, compile only)"
# `--output-dir .`: without it the scaffold lands in the TEMP dir (TEMP on Windows; /tmp on
# POSIX since 09-09 — it only ever appeared beside the source on Linux because TEMP was unset)
(cd src && rm -rf ide_gui_tui && "$ZEBRA" -c --check-full --gui-backend=tui --output-dir . ide.zbr >/dev/null 2>&1; [ -f ide_gui_tui/zig-out/bin/app ] || [ -f ide_gui_tui/zig-out/bin/app.exe ]) && echo PASS || { echo FAIL; fail=1; }
B=${LIBUI_BINDINGS:-}
if [ -z "$B" ]; then for c in /home/claude/libui-bindings /c/Projects/zig-libui-ng/src; do [ -f "$c/ui.zig" ] && B=$c; done; fi
if [ -n "$B" ]; then
  step "ide.zbr (libui_ng, sema vs $B)"
  (cd src && rm -rf ide_gui_libui_ng && "$ZEBRA" --gui-backend=libui_ng --scaffold-only --output-dir . ide.zbr >/dev/null 2>&1; cd ide_gui_libui_ng && zig build-obj -target x86_64-windows-gnu -fno-emit-bin --dep ui --dep sci -Mroot=src/main.zig --dep ui -Msci="$B/sci.zig" -Mui="$B/ui.zig") && echo PASS || { echo FAIL; fail=1; }
else
  step "libui sema: skipped (set LIBUI_BINDINGS)"
fi
step "gates runner on this project's manifest (headless CLI)"
# `zebra` must be on PATH for the manifest's commands; use the same binary as $ZEBRA
(cd src && PATH="$(dirname "$(readlink -f "$ZEBRA")"):$PATH" "$ZEBRA" gates.zbr -- ../zebra-ide.json sci_test buffers_test 2>&1 | tail -3 | grep -q "2/2 gates passed") && echo PASS || { echo FAIL; fail=1; }
rm -f src/*.zig
exit $fail

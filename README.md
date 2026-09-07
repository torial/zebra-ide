# zebra-ide

A lightweight IDE for Zebra, C and Zig, written in Zebra, on libui-ng + Scintilla,
talking to `zebra lsp` and `zebra debug`. Everything the IDE does beyond editing also
runs headless (`tools/check.sh`), so a window is never the only witness.

Status 2026-09-07: plan phases P0–P4 are landed and pass every headless gate in a
Linux container. **Nothing has yet been run on Windows with a window open.** The
first-run checklist below is written for exactly that moment.

## Prerequisites (Windows laptop)

- `C:\Projects\zebra-language` built: `zig build` (Zig 0.16). Put `zig-out\bin` on
  PATH, or always start the IDE through `zebra` (which sets `ZEBRA_COMPILER` for it).
- For the debugger only: LLVM's `lldb-dap.exe` on PATH (`winget install LLVM.LLVM`,
  then add `<LLVM>\bin`). Without it the Debug button reports it and everything else
  still works.
- For gates: the manifest commands use `bash tools/*.sh` — run the IDE from Git Bash,
  or edit `zebra-ide.json` to whatever runs your scripts.

## Run

```
cd C:\Projects\zebra-ide
zebra --gui-backend=libui_ng src\ide.zbr -- src\lsp.zbr src\buffers.zbr
```

Files after `--` open as tabs. `zebra-ide.json` in the current directory is the
project (Build / Run gates read it); this repo has one, and so does zebra-language.

## First-run checklist (in this order — each step is a witness for the code beneath it)

1. **A window with two tabs** and syntax colouring → the hatch, tabs, styler and the
   compiler's libui section all link and run (`examples\tabs_sci_smoke.zbr` in
   zebra-language is the smaller version if the IDE itself will not open).
2. **Status line says `zebra lsp`** and, after typing a deliberate error, a red
   squiggle + margin marker + boxed message appear within ~a second → LSP round trip.
3. **Type Enter after `def f()`** → the next line is indented. If not, the notify
   bridge is not live: that is expected until zig-libui-ng is pushed and the pin bumped
   (`tools\bump_libui_pin.sh <sha>` in zebra-language). Editing still works.
4. **Definition / References / Symbols / Rename** on `lsp.zbr` → panes fill; Jump
   works; rename across both open tabs.
5. **Build**, then **Run gates** → the pane fills, verdict lines appear, a failing gate's
   diagnostics are jumpable. (`zebra src\gates.zbr -- zebra-ide.json` is the same thing
   headless.)
6. Put the caret on a line in a small program and press **Breakpoint** (the margin
   click needs the notify bridge, which is absent until the pin bump — same as step
   3), then **Debug** → yellow arrow on that line, frames in the debugger pane; Next
   moves it; Stop ends it. If `lldb-dap` is missing, the debugger pane shows the
   relay's own message saying so and how to install it.

If a step fails, the thing to send back is the status line text plus, for 2/4/6, the
child's stderr: run `zebra lsp` / `zebra debug file.zbr` by hand and paste what it
prints. Every layer below the window has a headless test that has been seen red; the
window itself has none and has never been opened.

## What is where

| file | what | test |
|---|---|---|
| `src/ide.zbr` | the program (MVU; model is a class; panes are read-only editors) | tui compile + libui sema in `check.sh` |
| `src/lsp.zbr` | LSP client (initialize, didOpen/Change, definition, references, rename, symbols) | `lsp_client_test.zbr` vs real `zebra lsp` |
| `src/dap.zbr` | DAP client over `zebra debug` (breakpoints, step, frames) | `dap_client_test.zbr` vs real relay + lldb-dap |
| `src/transport.zbr` | Content-Length framing over `sys.spawnPiped`, shared by both | via the two above |
| `src/buffers.zbr` | open documents: paths, Scintilla document pointers, saved view state | `buffers_test.zbr` |
| `src/gates.zbr` | project manifest + non-blocking gate runner + diagnostic parser; CLI | `gates_test.zbr` |
| `src/sci.zbr` | Scintilla message ids (generated: `tools/gen_sci.py`) | `sci_test.zbr` |
| `src/textops.zbr` | WorkspaceEdit application, symbol outline, auto-indent decision (pure) | `textops_test.zbr` |
| `tools/check.sh` | the gate: all of the above, 9 steps | — |

## Known limits (stated, not hidden)

- Eight tabs (a fixed row: libui creates every widget on frame 0 and `uiTab` cannot
  relabel pages). Close one to open a ninth.
- No keyboard shortcuts: libui exposes no key events for Scintilla. Buttons for now.
- No variables pane yet. The DAP client can ask for scopes/variables, but the IDE
  does not show them; lldb has no Zig language plugin, so Locals would come back
  empty anyway (Globals and Registers do work at the protocol level).
- The tui backend only proves the program compiles; its editor is a text stub.
- Squiggles on `selfhost/CodeGen.zbr` lag by the compiler's own check time (~6 s).
- C and Zig: syntax colouring only. One language server (`zebra lsp`) is wired; C and
  Zig buffers are not sent to it, so they get no diagnostics or navigation until a
  clangd / zls client is added. The status line says so when such a file opens.
- **Plugins: not started.** Named in the ask; nothing in this tree yet. The intended
  route is Zebra's existing DynLib plugin system plus the gate manifest for anything
  that is a process.
- **Haiku: not started.** The GUI is built for Windows first; the compiler-side
  cross-platform work (libui-ng's Haiku backend, a Scintilla platform layer) is the
  long pole and lives in the plan, not here.
- Rename edits open buffers in memory (unsaved) and rewrites unopened files on disk
  in place, and says so in the status line. Close refuses once on unsaved changes.
- A gate that cannot run here (no lldb-dap) reports **SKIP**, not PASS — in the pane,
  in `gates.zbr`, and in `check.sh`.

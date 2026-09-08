# zebra-ide

A lightweight IDE for Zebra, C and Zig, written in Zebra, on libui-ng + Scintilla,
talking to `zebra lsp` and `zebra debug`. Everything the IDE does beyond editing also
runs headless (`tools/check.sh`), so a window is never the only witness.

Status 2026-09-08: plan phases P0–P4 are landed and pass every headless gate in a
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
- For C and Zig language support: `clangd` (part of LLVM, same install as lldb-dap)
  and `zls` (a zls release matching the Zig version; `zls-x86_64-windows.zip`) on PATH.
  Optional — without them those languages get colouring only.

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
   Open a `.c` or `.zig` file: the status line adds `clangd` / `zls` (or says it is not on
   PATH) and the same squiggles work there.
3. **Type Enter after `def f()`** → the next line is indented, and **Ctrl+S saves**.
   If not, the notify/key bridge is not live: expected until the compiler builds
   against the new zig-libui-ng. Two ways to get there — the quick one needs no push:
   `set ZEBRA_LIBUI_PATH=C:\Projects\zig-libui-ng` before starting the IDE (the
   generated project then points at your local checkout); the permanent one is push
   zig-libui-ng, then `tools\bump_libui_pin.sh <sha>` in zebra-language. Editing works
   either way.
4. **Definition / References / Symbols / Rename** on `lsp.zbr` → panes fill; Jump
   works; rename across both open tabs.
5. **Build**, then **Run gates** → the pane fills, verdict lines appear, a failing gate's
   diagnostics are jumpable. (`zebra src\gates.zbr -- zebra-ide.json` is the same thing
   headless.)
6. Put the caret on a line in a small program and press **Breakpoint** or F9 (the
   margin click and F9 need the bridge from step 3), then **Debug** or F5 → yellow
   arrow on that line, frames in the debugger pane; Next
   moves it; Stop ends it. Under the frames, Globals / Registers lists fill in a beat
   later (Locals says why it is empty). If `lldb-dap` is missing, the debugger pane
   shows the relay's own message saying so and how to install it.

If a step fails, the thing to send back is the status line text plus, for 2/4/6, the
child's stderr: run `zebra lsp` / `zebra debug file.zbr` by hand and paste what it
prints. Every layer below the window has a headless test that has been seen red; the
window itself has none and has never been opened.

## What is where

| file | what | test |
|---|---|---|
| `src/ide.zbr` | the program (MVU; model is a class; panes are read-only editors) | tui compile + libui sema in `check.sh` |
| `src/lsp.zbr` | LSP client (initialize, didOpen/Change, definition, references, rename, symbols); one instance per language server | `lsp_client_test.zbr`, `rename_workspace_test.zbr` vs real `zebra lsp`; `cross_lsp_test.zbr` vs clangd + zls |
| `src/dap.zbr` | DAP client over `zebra debug` (breakpoints, step, frames, scopes/variables) | `dap_client_test.zbr` vs real relay + lldb-dap |
| `src/transport.zbr` | Content-Length framing over `sys.spawnPiped`, shared by both | via the two above |
| `src/buffers.zbr` | open documents: paths, Scintilla document pointers, saved view state | `buffers_test.zbr` |
| `src/gates.zbr` | project manifest (gates + tools) + non-blocking runner + diagnostic parser; CLI | `gates_test.zbr`, `tools_test.zbr` |
| `src/sci.zbr` | Scintilla message ids (generated: `tools/gen_sci.py`) | `sci_test.zbr` |
| `src/keys.zbr` | the shortcut table (chord → action), pure | `keys_test.zbr` |
| `src/textops.zbr` | WorkspaceEdit application (in memory, and `applyWorkspaceEditToDisk` for unopened files), symbol outline, auto-indent decision | `textops_test.zbr`, `rename_workspace_test.zbr` |
| `tools/check.sh` | the gate: all of the above, 13 steps | — |

## Known limits (stated, not hidden)

- Tabs are a button row, one per open file, the current one in `[brackets]`; no
  limit (09-08: the compiler's GUI section now hides a widget the view stops
  emitting, so closed tabs disappear). A real `uiTab` strip is still not used —
  libui-ng cannot relabel a page and the row is the honest version of that.
- Keyboard shortcuts (09-08, needs the zig-libui-ng key shim → the pin bump): Ctrl+S
  save, Ctrl+W close, Ctrl+F find next, Ctrl+B build, Ctrl+Shift+B gates, F5 debug /
  continue, Shift+F5 stop, F9 breakpoint, F10 next, F11 step in, Shift+F11 step out,
  F12 definition, Shift+F12 references. The table is `src/keys.zbr` (keys_test checks
  it claims nothing Scintilla owns — Ctrl+C/V/X/Z/Y/A stay the editor's). Until the
  pin moves, the chords are inert and the buttons do everything.
- Variables: when the program stops, the debugger pane shows the top frame's scopes
  under the frames — Globals and Registers with values (first 40 each), and Locals,
  which is EMPTY for Zig programs because lldb has no Zig language plugin; the pane
  says so rather than showing a blank. (09-08; dap_client_test checks the scopes.)
- The tui backend only proves the program compiles; its editor is a text stub.
- Squiggles on `selfhost/CodeGen.zbr` lag by the compiler's own check time (~6 s).
- C and Zig have language servers now (09-08): a C buffer goes to `clangd`, a Zig
  buffer to `zls`, each started the first time such a file opens and each getting
  only its own language's files. Diagnostics, Definition, References, Symbols and
  Rename work through the same client as `zebra lsp` (cross_lsp_test proves all four
  on both). If `clangd` / `zls` is not on PATH the status line says so once and that
  language keeps colouring only. zls wants `zig` on PATH; clangd uses default flags
  unless a `compile_commands.json` is beside the file.
- **Plugins, kind 1 — process tools (09-08):** `"tools": [...]` in `zebra-ide.json`;
  each is a command with `${file}` `${dir}` `${root}` `${stem}` `${line}` `${col}`
  `${word}` substituted, run through the gate runner (never blocks), output in the
  gate pane. `"reload": true` re-reads the file after exit 0 (formatters), `"diags":
  true` marks `path:line:col: error:` lines in the editor, `"on": "save" | "open"`
  makes it a hook instead of a button. A dirty buffer is saved before a tool that
  names `${file}`. Design: wiki `concept_zebra-ide-plugins`. Kind 2 (in-process
  DLLs) waits on the compiler's shared-library round trip (BUG-356, pinned gate).
- **Haiku: not started.** The GUI is built for Windows first; the compiler-side
  cross-platform work (libui-ng's Haiku backend, a Scintilla platform layer) is the
  long pole and lives in the plan, not here.
- Rename edits open buffers in memory (unsaved) and rewrites unopened files on disk
  in place, and says so in the status line. Close refuses once on unsaved changes.
  `zebra lsp` (from 09-08) resolves the `use` graph from disk — the modules a file
  uses, and the same-directory files that use it — so a rename or Definition reaches
  modules that are not open. Dependents are found one directory deep, not recursively.
  (rename_workspace_test, 09-08 — the on-disk path had never run before it; its first
  run found two compiler bugs, BUG-352/353, and the open-documents-only server.)
- A gate that cannot run here (no lldb-dap) reports **SKIP**, not PASS — in the pane,
  in `gates.zbr`, and in `check.sh`.

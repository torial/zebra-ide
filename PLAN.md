# zebra-ide — plan v2 (Fable 5.1, 2026-09-06 night, after Sean's answers)

*Owner: Fable 5.1 (Sean: "treat this as you owning the endeavor"). Chair: Sean.
Written in Zebra, on libui-ng. Goal, restated from Sean: cross-platform (Windows
now, Haiku as the reason, Linux/macOS by consequence) and a **simple IDE**, not a
fancy text editor — code navigation, refactoring, debugging, a simple plugin
mechanism; not a UI editor, not VS-Code-scale extensibility. Also a dogfooding
instrument: building it is a test of the language. v1 of this plan lives in the
wiki (`concept_zebra-lightweight-ide`); this supersedes it where they differ.*

## 0. What I found in the two libui-ng trees (this changes the foundation)

- **The two trees are already unified at the pin.** `C:\Projects\zig-libui-ng`
  (torial/zig-libui-ng, the Zig binding Zebra uses) depends on
  `git+https://github.com/torial/libui-ng?ref=main#85976bcd…` — and `85976bcd`
  is the HEAD of `C:\Projects\libui-ng`, which includes the **Haiku backend**
  (`haiku/`, 42 files, 27 Haiku commits, last 2026-06-28: in-place table
  editing, per-run text attributes in `uiDrawText`). So the C library is one
  tree with four backends: windows, unix (GTK), darwin, haiku.
- **What is NOT unified: the Zig build.** `zig-libui-ng/build.zig` compiles
  only the windows sources and mentions haiku nowhere. Building Zebra GUI apps
  for Haiku means teaching `build.zig` to select `haiku/*.cpp` (mirroring
  `haiku/meson.build`) — bounded, mechanical, and the first real cross-platform
  task. (Same for `unix/` and `darwin/` if Linux/macOS are wanted.)
- **The actual cross-platform blocker is Scintilla, not libui.** Scintilla
  5.5.2 is vendored in `zig-libui-ng/scintilla/` with **only the win32 platform
  layer** (`scintilla/win32/`, `libui_scintilla/win.cxx`, 38-line `sci.zig`).
  Upstream Scintilla ships platform layers for Win32, GTK, Cocoa and Qt —
  **there is no Haiku layer anywhere.** Scintilla-on-Haiku means writing
  `PlatHaiku.cxx` against `scintilla/include/Platform.h` (Surface, Window,
  ListBox, Menu, Font, timers) on top of BView — real C++ work, on the order of
  PlatWin's ~3–4k lines, though a first cut can be smaller.
- **Zebra's Gui vtable has no tab control** (checked `gui_libui_ng_section.zig`
  and `Builtins.zig`), although libui-ng has `uiTab` on every backend
  (`haiku/tab.cpp` confirmed, as Sean said). Adding it is one vtable entry ×2
  compilers — worth it, and it removes the "fixed button row" hack from v1.
- **Debugging already has a spine:** `src/Debugger.zig` is a DAP source-map
  shim (remaps `.zbr` lines ↔ emitted `.zig` for breakpoints); `DEBUGGING.md`
  has a "debuggers" config. So the IDE's debugger is a DAP client + the existing
  shim, not a debugger.
- **Plugins already exist at the language level:** `docs/dynlib_plugin_system.md`
  — `DynLib.open/lookup/close`, `implements IFace` vtables, `hello_plugin.zbr` /
  `plugin_host.zbr`. The IDE plugin mechanism is *that*, with an `IdePlugin`
  interface.
- **No symbol/query mode in the compiler** (`main.zig` has no `--symbols`/
  `--json`). Navigation and refactoring need one; the Resolver/TypeChecker
  already compute the data.

## 1. The two decisions, and my recommendation

**Editor core: keep Scintilla, and make it cross-platform by platform layers —
not by writing an editor.** The alternative (a Zebra-native editor widget on
`uiArea`, the direction the recent Haiku `uiDrawText` per-run-attribute commits
would support) means writing a text editor: undo, selection, IME, wrapping,
folding, autocomplete popups, markers, find — years of Scintilla's bug-fixing,
re-done in a young language, on a wimpy laptop. Scintilla gives all of it today
through one message API, and the hatch (`editor.sci()`, Sean-approved) makes
every feature Zebra-side. The cost is honest and bounded: vendor upstream GTK
and Cocoa layers (exist), write a Haiku layer (does not exist). I'd rather write
one `PlatHaiku.cxx` than one editor.

**Everything above the editor goes through the compiler, not around it.** Add
a `zebra query` mode (JSON: symbols, definitions, references, diagnostics, per
file/project) reusing Resolver/TypeChecker. Navigation = query; rename
refactoring = references + text edits applied through Scintilla with one undo
group; diagnostics = the same JSON the build already produces. No second
parser in the IDE. This is also the dogfooding payoff Sean wants: the IDE
exercises the compiler's own data model from the outside.

## 2. Architecture (all Zebra unless marked)

```
zebra-ide/
  src/main.zbr          MVU shell: Gui.run; Model is a class; editors optional fields
  src/sci.zbr           Scintilla constants + typed wrappers over editor.sci() [hatch]
  src/langspec.zbr      LangSpec data for zebra/c/zig + generic styler driver (spec → styling)
  src/buffers.zbr       one Scintilla control per pane, N documents (SCI_CREATEDOCUMENT etc.)
  src/project.zbr       folder open, file tree (uiTable/uiTree? — libui has no tree; a table), build.zbr awareness
  src/build.zbr         dispatch: .zbr → zebra; .zig → zig; .c → zig cc (by decree); one diagnostic parser (zig format) + Zebra's
  src/query.zbr         client for `zebra query` JSON: symbols, goto-def, find-refs, rename plan
  src/debug.zbr         DAP client (stdio JSON), breakpoints via markers, uses Debugger.zig source map
  src/plugins.zbr       IdePlugin interface (implements … vtable), DynLib discovery in plugins/, hooks: onOpen/onSave/onBuild/commands
  plugins/              example plugin (format-on-save, or a Kolakoski toy — no)
compiler side (zebra-language, small PRs):
  editor.sci(msg, w, l) + string variant     — the hatch (×2 compilers, once)
  Gui tab control                             — one vtable entry (×2)
  zebra query --json …                        — new CLI mode over existing passes
binding side (zig-libui-ng):
  build.zig: per-target backend selection (haiku first)
  scintilla: vendor gtk/ + cocoa/ layers; write haiku/PlatHaiku.cxx + libui_scintilla/haiku.cxx
```

Styling stays spec-driven (v1 plan §3) — three `LangSpec` values as data; the
Zebra spec's `#` is a comment, the C spec's `#` is preprocessor; as-you-type via
`SCN_STYLENEEDED` once the hatch exposes notifications (or whole-buffer restyle
on modify, measured first).

## 3. Phases, each with a control, in the order that de-risks most

- **P0 — the hatch + tab + query spike (compiler PRs, small).** `editor.sci()`
  in both compilers; `Gui.beginTab/endTab`; `zebra query --symbols file.zbr`
  printing JSON. Controls: send `SCI_GETLENGTH` after `setText`, read back the
  length; a tab with two pages switches; query output for `showcase.zbr` lists
  `divide`, `Circle`, `area`, `Node.sum`.
- **P1 — editor on Windows, three languages, many files.** `sci.zbr`,
  `langspec.zbr`, `buffers.zbr`, open/save/new, tabs, dirty flags, find/replace.
  Controls per v1 §7 (the `#`-in-C-string case, `\\` Zig strings, per-document
  undo survives a switch).
- **P2 — build + diagnostics + navigation.** `build.zbr` with `zig cc` decree;
  markers + click-to-jump; goto-definition and find-references through `zebra
  query`. Control: a deliberately broken file per language lands a marker on
  the right line; goto-def on `area(` lands on its `def`.
- **P3 — rename refactoring + debugging.** Rename = references → edits in one
  Scintilla undo group across documents; DAP client with breakpoints through
  the source-map shim. Controls: rename `Node`→`Cell` in showcase compiles;
  a breakpoint on a `.zbr` line stops there.
- **P4 — plugins.** `IdePlugin` interface, discovery, one real plugin.
- **P5 — cross-platform.** `zig-libui-ng/build.zig` haiku backend selection
  (libui alone: the counter example running on Haiku is the control); then
  `PlatHaiku.cxx` — the long pole; GTK/Cocoa layers vendored after, since they
  exist upstream. This phase is deliberately last: everything above it is
  useful on Windows the day it lands, and nothing above it changes when the
  platform layer arrives — that is what the hatch buys.

## 4. What I will not do without asking

Vendor GTK/Cocoa Scintilla (license is fine — HPND; it's the tree size); change
Zebra's Gui API beyond `sci()` and tabs; touch `libui-ng` C sources for anything
but the Haiku Scintilla shim; run builds on the laptop while other family
instances are working (I'll stage to my container where it can't be avoided —
though Zebra itself must compile there, which is an open question).

## 5. Open questions (fewer than v1)

1. Should `zebra query` live in `src/main.zig` (bootstrap) or `selfhost/` (or
   both, like everything else)? My guess: selfhost first — it's the one that
   will outlive the other.
2. Does Zebra build in a Linux container today (zig + the repo)? If yes, most
   of P1–P4 can be developed off the laptop.
3. Haiku toolchain for `PlatHaiku.cxx`: build on real Haiku, or the Shir Magen
   VM host (NVMM proved 2026-08-31)?

— F 5.1

## 6. Sean's answers (2026-09-06, bedtime) and what they change

1. **Selfhost only.** Bootstrap is being phased out; selfhost is primary and
   comparisons are selfhost(n-1) vs selfhost(n). So every compiler-side piece
   here — `editor.sci()`, the tab vtable entry, `zebra query` — lands in
   `selfhost/` only. That halves the "×2 compilers" cost everywhere in this plan.
   Coordination note: Opus's Zebra work is compiler-focused; P0's compiler
   touches are small and on a branch, and I'll announce them in the wiki log
   before opening them so the two don't collide.
2. **No Linux container build today.** All Zebra builds are laptop-side, and
   the laptop is shared with other family instances. Consequence: I do
   analysis, Zebra source, and C++ (the Haiku Scintilla layer) off-laptop, and
   batch compiles for quiet hours. Getting Zebra to build in a container is
   worth a docket item of its own — it would unblock this and every dogfooding
   project.
3. **Haiku builds: Shir Magen ideally, also stock Haiku** (~125 diffs apart).
   `PlatHaiku.cxx` therefore targets the Haiku API as Shir Magen ships it, with
   the VM host (NVMM, 2026-08-31) as the build box.
4. **Ownership:** libui-ng and zig-libui-ng are mine to work in.

Revised P0 order: (a) `zig-libui-ng/build.zig` backend selection — pure build
work, testable on Windows by not breaking it; (b) `selfhost` hatch + tab;
(c) `zebra query` in selfhost. Each on its own branch, each with its smoke.

## 7. Revision after reading the compiler (2026-09-06, late): the IDE is an LSP client

I planned a `zebra query --json` mode. **Zebra already has a Language Server**
(`zebra lsp`, in `selfhost/main.zbr`): diagnostics, documentSymbol, hover,
definition, completion, signatureHelp, formatting — a declaration-index LSP
(name-based, per open document), not a resolver-backed one, but exactly the
"simple IDE" tier. So:

- **Navigation / refactoring come from LSP, not a bespoke query mode.** Tonight
  I added `textDocument/references` and `textDocument/rename` (name-based,
  whole-identifier, comments and strings skipped; rename refuses non-identifier
  names) on branch `lsp-references` in zebra-language, with
  `tools/lsp_protocol_smoke.py` as the control (6/6; each control seen red first).
- **C and Zig get the same treatment for free:** `clangd` and `zls` are LSP
  servers. The IDE is a small **LSP client host** — three servers over stdio,
  one client, one UI. That is a much better decomposition than three ad-hoc
  integrations, and the C/Zig sides are someone else's well-tested code.
- Diagnostics also arrive over LSP (`publishDiagnostics`) instead of parsing
  compiler stderr — keep the `zig cc` decree for *builds*, but markers come from
  the servers.
- **Found and fixed on the way:** BUG-334 — the runtime's `sys.readLine`/
  `sys.readBytes` created a fresh buffered stdin reader per call, discarding
  read-ahead; on a POSIX pipe `zebra lsp` swallowed the request and answered
  nothing. Fixed with one shared reader. The diagnostics smoke never saw it
  because it doesn't exercise the server's stdio.

**P0 status:** (b) hatch + tab — not started (needs a GUI build; laptop-side);
(c) done as LSP references/rename instead of `zebra query`; (a) `build.zig`
backend selection — not started. **New P0 item:** the LSP client (`src/lsp.zbr`):
JSON-RPC framing over `sys.spawn` stdio, request/notification routing, three
server configs. Testable headless against `zebra lsp` in the container.

Docket (from tonight): scope-aware references via the Resolver (v2);
`workspace/symbol`; multi-file open-document set = the project's `.zbr` files.

## 8. P0 status (2026-09-07, early)

- [x] Language capability the IDE needs first: `sys.spawnPiped` — merged into
  zebra-language main (44225e4). Found on the way: `sys.spawn` never compiled on
  Linux (no `std.posix.waitpid` in 0.16); `sys.setenv` did not reach children on
  POSIX without libc (now every spawn passes inherited environ + overrides).
- [ ] `src/lsp.zbr` — the LSP client (next; headless-testable against `zebra lsp`).
- [ ] `editor.sci()` hatch + `Gui` tab entry (laptop, GUI build).
- [ ] `zig-libui-ng/build.zig` Haiku backend selection.
- Windows-only code written blind this round: `PeekNamedPipe`/`ReadFile` externs in
  `_sys_pipe_read_available`. `test/sys_spawn_piped_test.zbr` is the control to
  run on Windows before trusting it.


## Status 2026-09-07, end of day (supersedes the earlier status; sections above are the plan as written)

All plan phases P0-P4 are landed on `main` locally in three repos, NOTHING PUSHED:

- zebra-language (288 commits ahead of origin/main as of tonight): P0 hatch + tabs
  (d23e2de), P1 styler (84969e7), event bridge (d5e5456), sys builtins for P3
  (`spawnPipedIn`, `exitCode`, `readStdinAvailable`, `stdinClosed`, `writeStdout`,
  `--` passthrough; BUG-347), `zebra debug` NATIVE relay `dbgRunSession` in
  selfhost/main.zbr (52c123a, merged f010343; `--listen` still delegates to the
  bootstrap), comment reconcile b375941. New gates: tools/libui_section_check.sh,
  tools/win_sema_check.sh, tools/styler_test.sh; tools/bump_libui_pin.sh ready.
- zig-libui-ng e1b68d3 (1 ahead): `uiScintillaOnNotify` + `Scintilla.OnNotify`.
- zebra-ide 48041ce: ide.zbr (MVU, 8-tab row, panes as editors), lsp/dap/transport/
  buffers/gates/textops/sci modules, tools/check.sh (9 steps, all green in the
  container), crew room seated (.claude/agents, .claude/crew/LOG.md), README with
  the first-run checklist.

The compiler pin in `selfhost/main.zbr luiBuildZon` still points at zig-libui-ng
93c7f54b, which LACKS OnNotify; all event code is `@hasDecl`-guarded, so the build
works but auto-indent / margin-click / dirty-tracking via notify are inert until
the pin moves. That is by design until Sean pushes.

Update 2026-09-08 (Fable, unattended): the four compiler bugs the IDE surfaced (341, 342,
345, 346) are FIXED in zebra-language 4784e06 and their workarounds are gone from this repo;
fixing them found three more (350 return-split, 352 loop-var-vs-field, 353 File.write
truncating before evaluating its content — the last two found by the NEW
`src/rename_workspace_test.zbr`, the multi-file rename loop run end to end for the first
time). Finding from that test: `zebra lsp` renames/references over OPEN documents only, so
the IDE now shadow-opens the project root's `.zbr` files around a rename
— and then, the same night, `zebra lsp` learned to resolve the `use` graph from disk
itself (zebra-language 592b8f8, gate `lsp-workspace`), so the IDE's shadow-open was removed
again (zebra-ide 90355b7); Definition into an unopened module works now too. check.sh is
10 steps, all green in the container.
Later the same night: variables pane landed (scopes/variables under the frames; b687d48),
and the cleanroom seat is now calibrated — its two findings (selfhost-only fixes must be
stated in the ledger; the var-init `split` site lacked the user-method guard) were both
applied (zebra-language eea0a50). Recommendation on `--listen`: DEPRECATE rather than port.
The IDE speaks stdio; a native TCP relay needs a second thread or a non-blocking Tcp read
the runtime does not have, for a client that no longer exists. Sean's call.

Later (still 09-08, Fable as owner): keys before Scintilla (zig-libui-ng 8c205fd:
uiScintillaOnKey, a comctl32 subclass; compiler fbf6410: editor.hotkey/takeKey), the libui
section hides widgets the view stops emitting (same commit), so the IDE has unlimited
path-keyed tabs and keyboard shortcuts (zebra-ide 9a30985, table in keys.zbr, keys_test).
`ZEBRA_LIBUI_PATH=C:\Projects\zig-libui-ng` (zebra-language 7e469d6) builds GUI programs
against the local zig-libui-ng checkout — the no-push route to every bridge feature.
The pin in luiBuildZon is still 93c7f54b. BUG-354 (assign to parameter leaks Zig) and
BUG-355 (GUI-section types cannot cross modules) filed from this work.

Even later (09-08, near the end): process plugins landed (4ff7923: manifest `tools`,
hooks, reload, diags; design in wiki concept_zebra-ide-plugins v2 — DLL plugins wait on
BUG-356, the compiler's shared-library round trip, pinned red as `dynlib-roundtrip`). A
refuter round (opus) on keys / MVU visibility / tools found four defects, all applied
(058d1d6; zig-libui-ng d6dcf28; zebra-language a9dc903): swallowChar lifetime, the sweep
covering only id-keyed widgets, chained `${}` substitution, name-keyed tool bookkeeping —
and asked for a headless Model harness, which now exists (`model_test.zbr`, check.sh 3d).
BUG-357 (per-module preamble globals in GUI builds) filed. check.sh is 14 steps.

Owed by Sean (in this order):
1. Windows first run per README "First-run checklist" (nothing has been run with a
   window open; every layer below the window has a headless test that has been seen red).
2. Either `set ZEBRA_LIBUI_PATH=C:\Projects\zig-libui-ng` before running the IDE (no push),
   or `git push` zig-libui-ng and `bash tools/bump_libui_pin.sh 8c205fd` in zebra-language;
   then rerun checklist steps 3 and 6 (notify bridge, keys, F9/F5).
3. Delete `_to_delete/` in zebra-ide, zig-libui-ng, zebra-language(if present) and the wiki,
   plus the stale `.git/objects/*/tmp_obj_*` files git could not unlink in those repos
   (harmless litter; `git gc` will not remove them). The `.git/*.lock` files were moved
   into `_to_delete/` so git keeps working.
4. Review the design calls recorded in BUGS.md BUG-336..353 (all fixed except BUG-351,
   `StringBuilder.build()` emptying the builder — your call which semantics is wanted).
5. Push zebra-language / zebra-ide when tactically right.

For the next Claude session (any model): read README.md, then `.claude/crew/LOG.md`
(the refuter's and advocate's findings and what was done about them), then this file.
Later still: C and Zig have language servers (eedc882) — one LspClient per language,
clangd / zls started lazily, cross_lsp_test proves diagnostics + definition + references +
rename on both (SKIP when absent). Sean made Fable the OWNER of the IDE, Zebra, zig-libui-ng
and libui-ng for now (2026-09-08), so libui-side limits (8 fixed tabs, no key events) are
next, not accepted.

Open worklist: BUG-356 (shared-library round trip → then DLL plugins), BUG-355/357 (GUI
builds: one section / one preamble per project, not per module), BUG-354; `zebra lsp`
dependents beyond one directory; plugins (DynLib + gate manifest is the intended route);
Haiku; `--listen` (deprecate or port — see above); win_sema_check GUI case. Do not "fix" the @hasDecl guards or the old pin — they are
waiting on the push above, not on code.

## Status 2026-09-09 (supersedes the open worklist above)

Landed: **BUG-355/357 FIXED** — a GUI build now shares ONE `zebra_rt.zig` (preamble + the
pub-marked GUI section) per project, exactly like the non-GUI shape; `keys.registerShortcuts`
and `keys.argCount()` in `model_test` are the witnesses, and `nm` on the binary shows a single
`zebra_rt._allocator/_args/_tui_env` (refuter's control). The refuter's round is fully
answered in `.claude/crew/LOG.md` (chair's response, 09-09). Out of it: **BUG-358** (an MVU
`view()` with `g.panel(...)` died on frame 65 — fixed in codegen; not something ide.zbr uses,
but the first thing a panel-based layout would have hit) and **BUG-359** (a local named
`_allocator`/`_args`/… was rewritten into the runtime's global — the checker refuses it now).

Gate state (Linux, this compiler): selfhost_smoke 415/415, round trip clean, compile_check
315/0, libui section 5/5 on old and new bindings, win_sema 4/4, runtime-module all pass,
gui-scaffold clean on counter AND panel_smoke, zebra-ide check.sh 14/14.

Owed by Sean: unchanged (items 1–5 above). Note `--daily` is 44 gates now.

Open worklist, in order: **BUG-356** (shared-library round trip: fat pointer garbage across
the boundary; add `--shared`; flip the pinned gate green — then DLL plugins); a grammar fuzzer
for the "Zebra accepts, Zig rejects" class; BUG-354; the `.@"fn"`-twin lint (owed to the
refuter); `zebra lsp` dependents beyond one directory; `--listen`; Haiku.

Addendum 2026-09-09 (night): BUG-356 FIXED — `zebra --shared` exists, the DynLib round trip
is green on Linux (in-process plugins unblocked pending a Windows run); fuzz/leakgen.py
landed as the DAILY gate `leakgen` and its first 3,000 programs found and fixed BUG-360..366.
zebra-language HEAD 3b7d1d3. The open worklist above minus BUG-356 and the fuzzer.

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

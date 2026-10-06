#!/usr/bin/env bash
# Build the zebra-ide .deb from an already-built binary. Run from the repository root:
#
#   bash packaging/linux/build_deb.sh BINARY VERSION OUT.deb
#
# VERSION is a Debian version (it must start with a digit; build.yml turns a `v0.1.0` tag
# into 0.1.0 and a master build into 0.0.0~dev.<run>+<sha>).
#
# Installs /usr/bin/zebra-ide (so `zebra-ide` starts from a project folder: the IDE takes
# its project root from the directory it is started in), a desktop entry, and the README.
# It does NOT depend on Zebra, which is not packaged for Debian: the IDE needs `zebra` on
# PATH at run time, and the description says so.
#
# Depends: is DERIVED from the binary's own dynamic links with dpkg-shlibdeps, never
# written by hand -- a hand list is exactly what drifts the day the libui backend links one
# more library. The derivation refuses (exit 2) if it comes back empty or without GTK 3,
# which every libui_ng build on Linux links: a derivation that cannot see GTK cannot see
# anything, and an empty Depends would install a binary that does not start.
set -euo pipefail

[ $# -eq 3 ] || { echo "usage: $0 BINARY VERSION OUT.deb" >&2; exit 2; }
bin=$1; ver=$2; out=$3
[ -f "$bin" ] || { echo "build_deb: no binary at $bin" >&2; exit 2; }
[ -f packaging/linux/zebra-ide.desktop ] || { echo "build_deb: run from the repository root" >&2; exit 2; }
case "$ver" in [0-9]*) ;; *) echo "build_deb: version '$ver' must start with a digit" >&2; exit 2 ;; esac

root=$(mktemp -d); work=$(mktemp -d)
trap 'rm -rf "$root" "$work"' EXIT

install -Dm755 "$bin" "$root/usr/bin/zebra-ide"
install -Dm644 packaging/linux/zebra-ide.desktop "$root/usr/share/applications/zebra-ide.desktop"
install -Dm644 README.md "$root/usr/share/doc/zebra-ide/README.md"

mkdir -p "$work/debian"
printf 'Source: zebra-ide\n\nPackage: zebra-ide\nArchitecture: amd64\n' > "$work/debian/control"
deps=$(cd "$work" && dpkg-shlibdeps -O -e "$root/usr/bin/zebra-ide" | sed -n 's/^shlibs:Depends=//p')
[ -n "$deps" ] || { echo "build_deb: dpkg-shlibdeps derived no dependencies -- refusing" >&2; exit 2; }
case "$deps" in
  *libgtk-3*) ;;
  *) echo "build_deb: derived Depends has no GTK 3 ('$deps') -- refusing" >&2; exit 2 ;;
esac
echo "build_deb: Depends: $deps"

mkdir -p "$root/DEBIAN"
cat > "$root/DEBIAN/control" <<EOF
Package: zebra-ide
Version: $ver
Architecture: amd64
Maintainer: torial <torial@users.noreply.github.com>
Installed-Size: $(du -sk "$root/usr" | cut -f1)
Depends: $deps
Section: devel
Priority: optional
Homepage: https://github.com/torial/zebra-ide
Description: IDE for the Zebra programming language
 A native editor for Zebra (libui-ng, Scintilla) with LSP diagnostics,
 build and run, project gates and a debugger. It needs the Zebra compiler
 on PATH at run time: https://github.com/torial/zebra-language#install
 Start it from a project folder: the folder it starts in is the project.
EOF

dpkg-deb --root-owner-group --build "$root" "$out"
dpkg-deb --info "$out"

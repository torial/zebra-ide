#!/usr/bin/env bash
# stays_up.sh LOG CMD... -- CI only (Linux, needs xvfb-run). Launches CMD under Xvfb and
# requires it to be STILL RUNNING 15 s later (timeout had to stop it: rc 124).
#
#   exit 0  still running at 15 s: no crash at startup
#   exit 1  CMD exited on its own (its rc and output are printed)
#   exit 2  the harness control failed -- this script cannot tell running from exited
#
# The CONTROL runs first, every time: a program that exits at once must read as exited, or
# a "startup OK" from here would mean nothing. It cannot tell running from HUNG: an init
# that blocks, or parks on a dialog, passes.
set -u
[ $# -ge 2 ] || { echo "usage: $0 LOG CMD..." >&2; exit 2; }
log=$1; shift

xvfb-run -a timeout 15 sh -c 'exit 3' > /dev/null 2>&1
crc=$?
if [ "$crc" = 124 ]; then
  echo "::error::harness control failed: a program that exits at once was reported as still running"
  exit 2
fi
echo "control: an immediately-exiting program is reported as exited (ok)"

xvfb-run -a timeout 15 "$@" > "$log" 2>&1
rc=$?
cat "$log"
if [ "$rc" != 124 ]; then
  echo "::error::$* exited with rc=$rc within 15 s of starting (expected to still be running)"
  exit 1
fi
echo "still running after 15 s: no crash at startup ($*)"

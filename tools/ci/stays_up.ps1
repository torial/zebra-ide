# stays_up.ps1 -Exe PATH -- CI only (Windows). Launches the program and requires it to be
# STILL RUNNING 15 s later, then stops it.
#
#   exit 0  still running at 15 s: no crash at startup
#   exit 1  the program exited on its own (its exit code and output are printed)
#   exit 2  the harness control failed -- this script cannot tell running from exited
#
# The CONTROL runs first, every time: a program that exits at once must read as exited.
# It cannot tell running from HUNG: an init that blocks, or parks on a dialog, passes.
param([Parameter(Mandatory = $true)][string]$Exe)

function StaysUp([string]$exe, [string[]]$argv) {
  $a = @{ FilePath = $exe; PassThru = $true; RedirectStandardOutput = 'run.out'; RedirectStandardError = 'run.err' }
  if ($argv) { $a.ArgumentList = $argv }
  $p = Start-Process @a
  Start-Sleep -Seconds 15
  $alive = -not $p.HasExited
  if ($alive) { Stop-Process -Id $p.Id -Force } else { $script:rc = $p.ExitCode }
  return $alive
}

if (StaysUp 'cmd.exe' @('/c', 'exit 3')) {
  Write-Host "::error::harness control failed: a program that exits at once was reported as still running"
  exit 2
}
Write-Host "control: an immediately-exiting program is reported as exited (ok)"

$up = StaysUp $Exe $null
Get-Content run.out, run.err -ErrorAction SilentlyContinue
if (-not $up) {
  Write-Host "::error::$Exe exited with rc=$script:rc within 15 s of starting (expected to still be running)"
  exit 1
}
Write-Host "still running after 15 s: no crash at startup ($Exe)"
exit 0

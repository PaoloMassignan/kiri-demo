# Thin wrapper: runs kiri CLI commands in whichever mode is active.
#
#   Native mode  — runs kiri directly against the demo workspace.
#                  Active when start-native.ps1 has written .kiri\.mode=native.
#   Docker mode  — forwards the command into the kiri container (original behaviour).
#                  Active when start.ps1 is used (default / rollback).
#
# Usage: .\scripts\kiri.ps1 <subcommand> [args...]
#   .\scripts\kiri.ps1 status
#   .\scripts\kiri.ps1 log --tail 10
#   .\scripts\kiri.ps1 explain --show-redacted

$DemoDir  = Split-Path -Parent $PSScriptRoot
$ModeFile = Join-Path $DemoDir ".kiri\.mode"

if ((Test-Path $ModeFile) -and ((Get-Content $ModeFile -Raw).Trim() -eq "native")) {
    # Native mode: run kiri directly with the demo workspace
    $env:KIRI_CONFIG = Join-Path $DemoDir ".kiri\config.native.local"
    $env:WORKSPACE   = $DemoDir
    & kiri @args
} else {
    # Docker mode (original behaviour)
    docker compose --project-directory $DemoDir exec kiri kiri @args
}

# Thin wrapper: forwards all arguments to kiri inside the Docker container.
#
# Usage: .\scripts\kiri.ps1 <subcommand> [args...]
#   .\scripts\kiri.ps1 status
#   .\scripts\kiri.ps1 log --tail 10
#   .\scripts\kiri.ps1 explain --show-redacted

$DemoDir = Split-Path -Parent $PSScriptRoot
docker compose --project-directory $DemoDir exec kiri kiri @args

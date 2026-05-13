# Builds the kiri-local Docker image from the kiri source repository.
#
# Usage: .\scripts\build-image.ps1 [-KiriRepo C:\path\to\kiri-repo]
#   If -KiriRepo is omitted, looks for the repo next to kiri-demo.
param(
    [string]$KiriRepo = ""
)

$DemoDir = Split-Path -Parent $PSScriptRoot

if ([string]::IsNullOrEmpty($KiriRepo)) {
    foreach ($candidate in @(
        "$DemoDir\..\kiri\kiri",
        "$DemoDir\..\kiri",
        "$DemoDir\..\AI-Layer\kiri\kiri",
        "$DemoDir\..\AI-Layer\kiri"
    )) {
        $resolved = [System.IO.Path]::GetFullPath($candidate)
        if (Test-Path "$resolved\Dockerfile") {
            $KiriRepo = $resolved
            break
        }
    }
}

if ([string]::IsNullOrEmpty($KiriRepo) -or -not (Test-Path "$KiriRepo\Dockerfile")) {
    $parent = [System.IO.Path]::GetFullPath("$DemoDir\..")
    Write-Error @"
Could not find the kiri repository next to kiri-demo.
Clone it first:
  cd $parent
  git clone https://github.com/PaoloMassignan/kiri.git
Then re-run this script from kiri-demo.

Or point to an existing clone:
  .\scripts\build-image.ps1 -KiriRepo C:\path\to\kiri
"@
    exit 1
}

Write-Host "Building kiri-local from: $KiriRepo" -ForegroundColor Cyan
docker build -t kiri-local $KiriRepo
Write-Host "Done. Image tagged as kiri-local." -ForegroundColor Green

# Starts Kiri in native mode (no Docker, no Ollama) and launches Claude Code
# or OpenCode with the proxy configured.  Stops the kiri process on exit.
#
# Usage:
#   .\scripts\start.ps1              # OAuth or API key mode
#   .\scripts\start.ps1 -Tool claude
#   .\scripts\start.ps1 -Tool opencode
#
# Prerequisites:
#   kiri.exe in PATH (download from https://github.com/PaoloMassignan/kiri/releases)
#
# Fallback to Docker: .\scripts\start-docker.ps1
param(
    [string]$Tool = ""
)

# Suppress Invoke-WebRequest progress bars (PS 5.1 shows them by default - very slow)
$ProgressPreference = 'SilentlyContinue'

$DemoDir = Split-Path -Parent $PSScriptRoot
Set-Location $DemoDir

# ── Check kiri binary ─────────────────────────────────────────────────────────
if (-not (Get-Command kiri -ErrorAction SilentlyContinue)) {
    Write-Error @"
'kiri' not found in PATH.

Install the native binary:
  https://github.com/PaoloMassignan/kiri/releases/latest

Or fall back to Docker mode:
  .\scripts\start-docker.ps1
"@
    exit 1
}

# ── Key setup ─────────────────────────────────────────────────────────────────
if (Test-Path ".env") {
    Get-Content ".env" | Where-Object { $_ -notmatch '^\s*#' -and $_ -match '=' } | ForEach-Object {
        $name, $value = $_ -split '=', 2
        $name = $name.Trim(); $value = $value.Trim()
        if ($name) { Set-Item "Env:$name" $value }
    }
}

$ApiKey = if ($env:ANTHROPIC_API_KEY) { $env:ANTHROPIC_API_KEY } else { "" }

if ([string]::IsNullOrEmpty($ApiKey)) {
    Write-Host "Mode: OAuth passthrough" -ForegroundColor Cyan
    New-Item -ItemType Directory -Force -Path ".kiri" | Out-Null
    if (-not (Test-Path ".kiri\upstream.key")) {
        "oauth-passthrough-placeholder" | Out-File ".kiri\upstream.key" -Encoding ascii -NoNewline
    }
    $OAuthPassthrough = "true"
} else {
    Write-Host "Mode: API key ($($ApiKey.Substring(0, [Math]::Min(8, $ApiKey.Length)))...)" -ForegroundColor Cyan
    if (-not (Test-Path ".kiri\upstream.key")) {
        Write-Error ".kiri\upstream.key not found.`nCreate it: 'sk-ant-YOUR-KEY' | Out-File .kiri\upstream.key"
        exit 1
    }
    $OAuthPassthrough = "false"
}

# ── Generate runtime config ───────────────────────────────────────────────────
Write-Host "Note: L3 classifier uses Ollama when available; otherwise fails-open (L1+L2 active)." -ForegroundColor DarkGray
$ConfigLines = @(
    "oauth_passthrough: $OAuthPassthrough",
    "similarity_threshold: 0.75",
    "hard_block_threshold: 0.90",
    "action: sanitize",
    "proxy_port: 8765",
    "embedding_model: all-MiniLM-L6-v2"
)
# Write UTF-8 without BOM (Out-File -Encoding utf8 adds BOM in PS 5.1)
[System.IO.File]::WriteAllLines(
    (Join-Path $DemoDir ".kiri\config.native.local"),
    $ConfigLines
)

# ── Set mode sentinel ─────────────────────────────────────────────────────────
[System.IO.File]::WriteAllText(
    (Join-Path $DemoDir ".kiri\.mode"), "native"
)

# ── Check port availability ───────────────────────────────────────────────────
$portCheck = netstat -ano 2>$null | Select-String "127\.0\.0\.1:8765\s"
if (-not $portCheck) { $portCheck = netstat -ano 2>$null | Select-String "0\.0\.0\.0:8765\s" }
if ($portCheck) {
    $existingPid = ($portCheck[0].ToString().Trim() -split '\s+')[-1]
    Write-Host "Port 8765 is already in use (PID $existingPid)." -ForegroundColor Red
    Write-Host "Stop the existing process first:" -ForegroundColor Red
    Write-Host "  Stop-Process -Id $existingPid -Force" -ForegroundColor Yellow
    Write-Host "Then re-run this script." -ForegroundColor DarkGray
    exit 1
}

# ── Start kiri serve ──────────────────────────────────────────────────────────
Write-Host "Starting Kiri (native)..." -ForegroundColor Yellow
$env:KIRI_CONFIG            = Join-Path $DemoDir ".kiri\config.native.local"
$env:WORKSPACE              = $DemoDir
if (Test-Path ".kiri\upstream.key") {
    $env:KIRI_UPSTREAM_KEY_FILE = Join-Path $DemoDir ".kiri\upstream.key"
}

$KiriLog = Join-Path $DemoDir ".kiri\kiri-serve.log"
$KiriErr = Join-Path $DemoDir ".kiri\kiri-serve.err"
$KiriProc = Start-Process kiri -ArgumentList "serve" -PassThru -NoNewWindow `
    -RedirectStandardOutput $KiriLog -RedirectStandardError $KiriErr

# ── Health check (120 s - first run extracts a large binary) ─────────────────
Write-Host -NoNewline "Waiting for Kiri to be ready"
$ready = $false
for ($i = 0; $i -lt 60; $i++) {
    Start-Sleep -Seconds 2
    try {
        $null = Invoke-WebRequest -Uri "http://localhost:8765/health" -UseBasicParsing -TimeoutSec 2
        $ready = $true; break
    } catch {}
    Write-Host -NoNewline "."
}
Write-Host ""
if (-not $ready) {
    Write-Host "Kiri did not become ready in 120 s." -ForegroundColor Red
    $errTail = Get-Content $KiriErr -ErrorAction SilentlyContinue | Select-Object -Last 6
    if ($errTail) {
        Write-Host "`nError log (last lines):" -ForegroundColor Yellow
        $errTail | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkRed }
    }
    Write-Host "`nFull logs:" -ForegroundColor DarkGray
    Write-Host "  Get-Content .kiri\kiri-serve.log" -ForegroundColor DarkGray
    Write-Host "  Get-Content .kiri\kiri-serve.err" -ForegroundColor DarkGray
    Stop-Process -Id $KiriProc.Id -ErrorAction SilentlyContinue
    Remove-Item ".kiri\.mode" -ErrorAction SilentlyContinue
    exit 1
}
Write-Host "Kiri ready." -ForegroundColor Green

# ── Pick tool ─────────────────────────────────────────────────────────────────
if ([string]::IsNullOrEmpty($Tool)) {
    if   (Get-Command claude   -ErrorAction SilentlyContinue) { $Tool = "claude" }
    elseif (Get-Command opencode -ErrorAction SilentlyContinue) { $Tool = "opencode" }
    if ([string]::IsNullOrEmpty($Tool)) {
        Write-Host ""
        Write-Host "Neither 'claude' nor 'opencode' found in PATH." -ForegroundColor Red
        Write-Host "Kiri is running on http://localhost:8765" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Install Claude Code:  https://claude.ai/code" -ForegroundColor DarkGray
        Write-Host "Install OpenCode:     https://opencode.ai" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "Or start your tool manually with:" -ForegroundColor DarkGray
        Write-Host '  $env:ANTHROPIC_BASE_URL = "http://localhost:8765"' -ForegroundColor DarkGray
        Write-Host "  claude   # or opencode" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "Press Ctrl+C to stop Kiri when done." -ForegroundColor DarkGray
        # Keep kiri running - wait for Ctrl+C
        try { while ($true) { Start-Sleep -Seconds 5 } } finally {}
        Stop-Process -Id $KiriProc.Id -ErrorAction SilentlyContinue
        Remove-Item ".kiri\.mode" -ErrorAction SilentlyContinue
        exit 0
    }
}
Write-Host "Launching $Tool through Kiri..." -ForegroundColor Cyan

# ── Set env, launch, restore ──────────────────────────────────────────────────
$prevBaseUrl = $env:ANTHROPIC_BASE_URL
$prevApiKey  = $env:ANTHROPIC_API_KEY

$env:ANTHROPIC_BASE_URL = "http://localhost:8765"
if ([string]::IsNullOrEmpty($ApiKey)) {
    Remove-Item Env:ANTHROPIC_API_KEY -ErrorAction SilentlyContinue
} else {
    $env:ANTHROPIC_API_KEY = $ApiKey
}

try {
    & $Tool
} finally {
    # Restore env
    if ($null -eq $prevBaseUrl) { Remove-Item Env:ANTHROPIC_BASE_URL -ErrorAction SilentlyContinue }
    else { $env:ANTHROPIC_BASE_URL = $prevBaseUrl }
    if ($null -eq $prevApiKey) { Remove-Item Env:ANTHROPIC_API_KEY -ErrorAction SilentlyContinue }
    else { $env:ANTHROPIC_API_KEY = $prevApiKey }
    Remove-Item Env:KIRI_CONFIG -ErrorAction SilentlyContinue
    Remove-Item Env:WORKSPACE   -ErrorAction SilentlyContinue
    Remove-Item Env:KIRI_UPSTREAM_KEY_FILE -ErrorAction SilentlyContinue
    # Stop kiri and clear sentinel
    Stop-Process -Id $KiriProc.Id -ErrorAction SilentlyContinue
    Remove-Item ".kiri\.mode" -ErrorAction SilentlyContinue
    Write-Host ""
    Write-Host "Session ended - Kiri stopped." -ForegroundColor DarkGray
    Write-Host "To start a new session: .\scripts\start.ps1" -ForegroundColor DarkGray
}

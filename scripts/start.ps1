# Starts Kiri and launches Claude Code or OpenCode with the proxy configured.
# Restores the original environment on exit.
#
# Usage: .\scripts\start.ps1 [-Tool claude|opencode]
#   Omit -Tool to auto-detect which tool is installed.
param(
    [string]$Tool = ""
)

$DemoDir = Split-Path -Parent $PSScriptRoot
Set-Location $DemoDir

# ── Load .env ──────────────────────────────────────────────────────────────────
if (Test-Path ".env") {
    Get-Content ".env" | Where-Object { $_ -notmatch '^\s*#' -and $_ -match '\S' -and $_ -match '=' } | ForEach-Object {
        $name, $value = $_ -split '=', 2
        $name = $name.Trim()
        $value = $value.Trim()
        if ($name) { Set-Item "Env:$name" $value }
    }
}

$BaseUrl = if ($env:ANTHROPIC_BASE_URL) { $env:ANTHROPIC_BASE_URL } else { "http://localhost:8765" }
$ApiKey  = if ($env:ANTHROPIC_API_KEY)  { $env:ANTHROPIC_API_KEY  } else { "" }

# ── OAuth vs API key mode ──────────────────────────────────────────────────────
$OAuthMode = [string]::IsNullOrEmpty($ApiKey)
if ($OAuthMode) {
    Write-Host "Mode: OAuth passthrough" -ForegroundColor Cyan
    New-Item -ItemType Directory -Force -Path ".kiri" | Out-Null
    if (-not (Test-Path ".kiri\upstream.key")) {
        "oauth-passthrough-placeholder" | Out-File -FilePath ".kiri\upstream.key" -Encoding ascii -NoNewline
    }
} else {
    Write-Host "Mode: API key ($($ApiKey.Substring(0, [Math]::Min(8, $ApiKey.Length)))...)" -ForegroundColor Cyan
    if (-not (Test-Path ".kiri\upstream.key")) {
        Write-Error ".kiri\upstream.key not found.`nCreate it: 'sk-ant-YOUR-KEY' | Out-File .kiri\upstream.key"
        exit 1
    }
}

# ── Docker check ───────────────────────────────────────────────────────────────
& docker ps *>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Docker not running - starting Docker Desktop..." -ForegroundColor Yellow
    Start-Process "C:\Program Files\Docker\Docker\Docker Desktop.exe"
    $ready = $false
    for ($i = 0; $i -lt 30; $i++) {
        Start-Sleep -Seconds 2
        & docker ps *>$null
        if ($LASTEXITCODE -eq 0) { $ready = $true; break }
    }
    if (-not $ready) { Write-Error "Docker did not start in 60 s."; exit 1 }
    Write-Host "Docker ready." -ForegroundColor Green
}

# ── Start Kiri if not running ──────────────────────────────────────────────────
$startedKiri = $false
$running = docker compose --project-directory $DemoDir ps --services --filter status=running 2>$null | Select-String "^kiri$"
if (-not $running) {
    Write-Host "Starting Kiri..." -ForegroundColor Yellow
    $env:WORKSPACE_HOST = $DemoDir
    docker compose --project-directory $DemoDir up -d

    Write-Host -NoNewline "Waiting for Kiri to be ready"
    $ready = $false
    for ($i = 0; $i -lt 30; $i++) {
        Start-Sleep -Seconds 2
        $check = Test-NetConnection -ComputerName localhost -Port 8765 -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        if ($check.TcpTestSucceeded) { $ready = $true; break }
        Write-Host -NoNewline "."
    }
    Write-Host ""
    if (-not $ready) {
        Write-Error "Kiri did not become ready in 60 s.`nCheck logs: docker compose --project-directory '$DemoDir' logs kiri"
        exit 1
    }
    Write-Host "Kiri ready." -ForegroundColor Green
    $startedKiri = $true
} else {
    Write-Host "Kiri already running." -ForegroundColor Green
}

# ── Pick tool ──────────────────────────────────────────────────────────────────
if ([string]::IsNullOrEmpty($Tool)) {
    if (Get-Command claude -ErrorAction SilentlyContinue)    { $Tool = "claude" }
    elseif (Get-Command opencode -ErrorAction SilentlyContinue) { $Tool = "opencode" }
    else {
        Write-Error "Neither 'claude' nor 'opencode' found in PATH.`nInstall one and retry, or pass: .\scripts\start.ps1 -Tool claude"
        exit 1
    }
}
Write-Host "Launching $Tool through Kiri..." -ForegroundColor Cyan

# ── Set env, launch, restore ───────────────────────────────────────────────────
$prevBaseUrl = $env:ANTHROPIC_BASE_URL
$prevApiKey  = $env:ANTHROPIC_API_KEY

$env:ANTHROPIC_BASE_URL = "http://localhost:8765"
if ($OAuthMode) {
    Remove-Item Env:ANTHROPIC_API_KEY -ErrorAction SilentlyContinue
} else {
    $env:ANTHROPIC_API_KEY = $ApiKey
}

try {
    & $Tool
} finally {
    if ($null -eq $prevBaseUrl) { Remove-Item Env:ANTHROPIC_BASE_URL -ErrorAction SilentlyContinue }
    else { $env:ANTHROPIC_BASE_URL = $prevBaseUrl }

    if ($null -eq $prevApiKey) { Remove-Item Env:ANTHROPIC_API_KEY -ErrorAction SilentlyContinue }
    else { $env:ANTHROPIC_API_KEY = $prevApiKey }
}

Write-Host "Session ended. Kiri is still running." -ForegroundColor DarkGray
Write-Host "To stop: docker compose --project-directory '$DemoDir' down" -ForegroundColor DarkGray

# Starts Kiri and launches Claude Code or OpenCode with the proxy configured.
# Restores the original environment on exit.
#
# Usage:
#   .\scripts\start.ps1                   # OAuth or API key mode (Anthropic/Claude cloud)
#   .\scripts\start.ps1 -Local            # Local Ollama mode (no cloud account needed)
#   .\scripts\start.ps1 -Tool opencode    # Force a specific tool
param(
    [string]$Tool  = "",
    [switch]$Local
)

$DemoDir = Split-Path -Parent $PSScriptRoot
Set-Location $DemoDir

# --- Docker check -------------------------------------------------------------
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

# --- Mode setup ---------------------------------------------------------------
$ComposeArgs = @("--project-directory", $DemoDir)

if ($Local) {
    Write-Host "Mode: Local LLM (Ollama/qwen2.5:3b via LiteLLM - no cloud account needed)" -ForegroundColor Cyan
    New-Item -ItemType Directory -Force -Path ".kiri" | Out-Null
    if (-not (Test-Path ".kiri\upstream.key")) {
        "local-mode-placeholder" | Out-File -FilePath ".kiri\upstream.key" -Encoding ascii -NoNewline
    }
    # Tell kiri to forward to LiteLLM instead of the real Anthropic API
    $env:KIRI_UPSTREAM_URL = "http://litellm:4000"
    $ComposeArgs += @("--profile", "local")
    $ToolApiKey = "sk-ant-local-demo"
} else {
    # --- Load .env ------------------------------------------------------------
    if (Test-Path ".env") {
        Get-Content ".env" | Where-Object { $_ -notmatch '^\s*#' -and $_ -match '\S' -and $_ -match '=' } | ForEach-Object {
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
            "oauth-passthrough-placeholder" | Out-File -FilePath ".kiri\upstream.key" -Encoding ascii -NoNewline
        }
    } else {
        Write-Host "Mode: API key ($($ApiKey.Substring(0, [Math]::Min(8, $ApiKey.Length)))...)" -ForegroundColor Cyan
        if (-not (Test-Path ".kiri\upstream.key")) {
            Write-Error ".kiri\upstream.key not found.`nCreate it: 'sk-ant-YOUR-KEY' | Out-File .kiri\upstream.key"
            exit 1
        }
    }
    $ToolApiKey = $ApiKey
}

# --- Start services if not running --------------------------------------------
$running = docker compose @ComposeArgs ps --services --filter status=running 2>$null | Select-String "^kiri$"
if (-not $running) {
    Write-Host "Starting Kiri..." -ForegroundColor Yellow
    $env:WORKSPACE_HOST = $DemoDir
    docker compose @ComposeArgs up -d

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
} else {
    Write-Host "Kiri already running." -ForegroundColor Green
}

# --- Pick tool ----------------------------------------------------------------
if ([string]::IsNullOrEmpty($Tool)) {
    if ($Local) {
        # Local mode: prefer OpenCode (Claude Code needs a real Anthropic session)
        if (Get-Command opencode -ErrorAction SilentlyContinue)    { $Tool = "opencode" }
        elseif (Get-Command claude -ErrorAction SilentlyContinue)  { $Tool = "claude" }
    } else {
        if (Get-Command claude -ErrorAction SilentlyContinue)      { $Tool = "claude" }
        elseif (Get-Command opencode -ErrorAction SilentlyContinue){ $Tool = "opencode" }
    }
    if ([string]::IsNullOrEmpty($Tool)) {
        Write-Error "Neither 'claude' nor 'opencode' found in PATH.`nInstall one and retry, or pass: .\scripts\start.ps1 -Tool opencode"
        exit 1
    }
}
Write-Host "Launching $Tool through Kiri..." -ForegroundColor Cyan

# --- Set env, launch, restore -------------------------------------------------
$prevBaseUrl = $env:ANTHROPIC_BASE_URL
$prevApiKey  = $env:ANTHROPIC_API_KEY

$env:ANTHROPIC_BASE_URL = "http://localhost:8765"
if ([string]::IsNullOrEmpty($ToolApiKey)) {
    Remove-Item Env:ANTHROPIC_API_KEY -ErrorAction SilentlyContinue
} else {
    $env:ANTHROPIC_API_KEY = $ToolApiKey
}

try {
    & $Tool
} finally {
    if ($null -eq $prevBaseUrl) { Remove-Item Env:ANTHROPIC_BASE_URL -ErrorAction SilentlyContinue }
    else { $env:ANTHROPIC_BASE_URL = $prevBaseUrl }

    if ($null -eq $prevApiKey) { Remove-Item Env:ANTHROPIC_API_KEY -ErrorAction SilentlyContinue }
    else { $env:ANTHROPIC_API_KEY = $prevApiKey }

    if ($Local) { Remove-Item Env:KIRI_UPSTREAM_URL -ErrorAction SilentlyContinue }
}

Write-Host "Session ended. Kiri is still running." -ForegroundColor DarkGray
Write-Host "To stop: docker compose --project-directory '$DemoDir' down" -ForegroundColor DarkGray

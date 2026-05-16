# Starts Kiri in native mode (no Docker, no Ollama) and launches Claude Code
# or OpenCode with the proxy configured.  Stops the kiri process on exit.
#
# Usage:
#   .\scripts\start-native.ps1              # OAuth or API key mode
#   .\scripts\start-native.ps1 -Tool claude
#   .\scripts\start-native.ps1 -Tool opencode
#
# Prerequisites:
#   kiri.exe in PATH (download from https://github.com/PaoloMassignan/kiri/releases)
#   For L3 classifier: run "kiri install" as Administrator first.
#
# Fallback to Docker: .\scripts\start.ps1
param(
    [string]$Tool = ""
)

$DemoDir = Split-Path -Parent $PSScriptRoot
Set-Location $DemoDir

# ── Check kiri binary ─────────────────────────────────────────────────────────
if (-not (Get-Command kiri -ErrorAction SilentlyContinue)) {
    Write-Error @"
'kiri' not found in PATH.

Install the native binary:
  https://github.com/PaoloMassignan/kiri/releases/latest

Or fall back to Docker mode:
  .\scripts\start.ps1
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

# ── Detect GGUF model ─────────────────────────────────────────────────────────
$ModelFilename = "qwen2.5-3b-q4.gguf"
$ModelPath     = "C:\ProgramData\Kiri\models\$ModelFilename"

if (Test-Path $ModelPath) {
    $LlmBackend  = "llama_cpp"
    $ModelLine   = "llm_model_path: $($ModelPath -replace '\\','/')"
    Write-Host "Local AI: enabled (llama_cpp, $ModelFilename)" -ForegroundColor Green
} else {
    $LlmBackend  = "ollama"
    $ModelLine   = ""
    Write-Host "Local AI: disabled (model not found at $ModelPath)" -ForegroundColor Yellow
    Write-Host "  L3 classifier will fail-open — L1 and L2 remain fully active." -ForegroundColor DarkGray
    Write-Host "  To enable L3: run 'kiri install' as Administrator." -ForegroundColor DarkGray
}

# ── Generate runtime config ───────────────────────────────────────────────────
$ConfigLines = @(
    "oauth_passthrough: $OAuthPassthrough",
    "similarity_threshold: 0.75",
    "hard_block_threshold: 0.90",
    "action: sanitize",
    "proxy_port: 8765",
    "embedding_model: all-MiniLM-L6-v2",
    "llm_backend: $LlmBackend"
)
if ($ModelLine) { $ConfigLines += $ModelLine }
$ConfigLines | Out-File ".kiri\config.native.local" -Encoding utf8

# ── Set mode sentinel ─────────────────────────────────────────────────────────
"native" | Out-File ".kiri\.mode" -Encoding ascii -NoNewline

# ── Start kiri serve ──────────────────────────────────────────────────────────
Write-Host "Starting Kiri (native)..." -ForegroundColor Yellow
$env:KIRI_CONFIG            = Join-Path $DemoDir ".kiri\config.native.local"
$env:WORKSPACE              = $DemoDir
if (Test-Path ".kiri\upstream.key") {
    $env:KIRI_UPSTREAM_KEY_FILE = Join-Path $DemoDir ".kiri\upstream.key"
}

$KiriProc = Start-Process kiri -ArgumentList "serve" -PassThru -NoNewWindow

# ── Health check ──────────────────────────────────────────────────────────────
Write-Host -NoNewline "Waiting for Kiri to be ready"
$ready = $false
for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Seconds 2
    try {
        $null = Invoke-WebRequest -Uri "http://localhost:8765/health" -UseBasicParsing -TimeoutSec 2
        $ready = $true; break
    } catch {}
    Write-Host -NoNewline "."
}
Write-Host ""
if (-not $ready) {
    Write-Error "Kiri did not become ready in 60 s.`nCheck if port 8765 is already in use."
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
        Write-Error "Neither 'claude' nor 'opencode' found.`nInstall one or pass: .\scripts\start-native.ps1 -Tool opencode"
        Stop-Process -Id $KiriProc.Id -ErrorAction SilentlyContinue
        Remove-Item ".kiri\.mode" -ErrorAction SilentlyContinue
        exit 1
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
    Write-Host "Session ended. Kiri stopped." -ForegroundColor DarkGray
}

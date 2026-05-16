#Requires -Version 5.1
<#
.SYNOPSIS
  Deploys the Telegram lead proxy as a Cloudflare Worker.

.DESCRIPTION
  Run from the repo root in PowerShell. Pass credentials as parameters or env vars.
  Requires curl.exe (ships with Windows 10/11).

.EXAMPLE
  .\deploy-worker.ps1 `
    -CF_ACCOUNT "your-account-id" `
    -CF_TOKEN "your-cf-api-token" `
    -TG_TOKEN "your-telegram-bot-token"

.EXAMPLE
  $env:CF_ACCOUNT = "..."; $env:CF_TOKEN = "..."; $env:TG_TOKEN = "..."
  .\deploy-worker.ps1
#>
[CmdletBinding()]
param(
    [string]$CF_ACCOUNT = $env:CF_ACCOUNT,
    [string]$CF_TOKEN   = $env:CF_TOKEN,
    [string]$TG_TOKEN   = $env:TG_TOKEN,
    [string]$SCRIPT_NAME    = "shanset-tg-proxy",
    [string]$TG_CHAT_ID     = "407721399",
    [string]$ALLOWED_ORIGIN = "https://alexdmitrievi.github.io"
)

$ErrorActionPreference = "Stop"

function Step([int]$n,[string]$m) { Write-Host "`n[$n/5] $m" -ForegroundColor Cyan }
function OK([string]$m)   { Write-Host "  OK: $m"   -ForegroundColor Green }
function Bad([string]$m)  { Write-Host "  FAIL: $m" -ForegroundColor Red; exit 1 }

if (-not $CF_ACCOUNT) { Bad "CF_ACCOUNT not set — pass -CF_ACCOUNT or set `$env:CF_ACCOUNT" }
if (-not $CF_TOKEN)   { Bad "CF_TOKEN not set — pass -CF_TOKEN or set `$env:CF_TOKEN" }
if (-not $TG_TOKEN)   { Bad "TG_TOKEN not set — pass -TG_TOKEN or set `$env:TG_TOKEN" }

$workerFile = Join-Path $PSScriptRoot "workers\telegram-proxy.js"
if (-not (Test-Path $workerFile)) {
    Bad "$workerFile not found. Run from repo root."
}

$curlCmd = Get-Command curl.exe -ErrorAction SilentlyContinue
if (-not $curlCmd) { Bad "curl.exe not found. Install via 'winget install curl' or update Windows." }

$api = "https://api.cloudflare.com/client/v4"
$headers = @{ "Authorization" = "Bearer $CF_TOKEN" }

# -------------------------------------------------------------
Step 1 "Verify Cloudflare token"
try {
    $v = Invoke-RestMethod -Uri "$api/accounts/$CF_ACCOUNT/tokens/verify" -Headers $headers -Method GET
    if (-not $v.success) { Bad "Token verify failed (response: $($v | ConvertTo-Json -Compress))" }
    OK "Token is active"
} catch { Bad "Token verify request failed: $($_.Exception.Message)" }

# -------------------------------------------------------------
Step 2 "Upload Worker script ($SCRIPT_NAME)"
$meta = '{"main_module":"worker.js","compatibility_date":"2025-01-01"}'
$resp = & curl.exe -sS -X PUT "$api/accounts/$CF_ACCOUNT/workers/scripts/$SCRIPT_NAME" `
    -H "Authorization: Bearer $CF_TOKEN" `
    -F "metadata=$meta;type=application/json" `
    -F "worker.js=@$workerFile;type=application/javascript+module;filename=worker.js" 2>&1
if ($resp -notmatch '"success":true') { Bad "Worker upload failed:`n$resp" }
OK "Worker uploaded"

# -------------------------------------------------------------
Step 3 "Set encrypted secrets"
$secrets = [ordered]@{
    "TELEGRAM_BOT_TOKEN" = $TG_TOKEN
    "TELEGRAM_CHAT_ID"   = $TG_CHAT_ID
    "ALLOWED_ORIGIN"     = $ALLOWED_ORIGIN
}
foreach ($name in $secrets.Keys) {
    $body = @{ name = $name; text = $secrets[$name]; type = "secret_text" } | ConvertTo-Json -Compress
    try {
        $r = Invoke-RestMethod -Uri "$api/accounts/$CF_ACCOUNT/workers/scripts/$SCRIPT_NAME/secrets" `
            -Method PUT -Headers $headers -ContentType "application/json" -Body $body
        if (-not $r.success) { Bad "Secret $name failed (response: $($r | ConvertTo-Json -Compress))" }
        OK "Secret $name set"
    } catch { Bad "Secret $name failed: $($_.Exception.Message)" }
}

# -------------------------------------------------------------
Step 4 "Enable workers.dev subdomain"
$body = '{"enabled":true,"previews_enabled":false}'
try {
    $e = Invoke-RestMethod -Uri "$api/accounts/$CF_ACCOUNT/workers/scripts/$SCRIPT_NAME/subdomain" `
        -Method POST -Headers $headers -ContentType "application/json" -Body $body
    if (-not $e.success) { Bad "Subdomain enable failed (response: $($e | ConvertTo-Json -Compress))" }
    OK "workers.dev URL enabled"
} catch { Bad "Subdomain enable failed: $($_.Exception.Message)" }

# -------------------------------------------------------------
Step 5 "Resolve URL"
try {
    $s = Invoke-RestMethod -Uri "$api/accounts/$CF_ACCOUNT/workers/subdomain" -Headers $headers
    $sub = $s.result.subdomain
    if (-not $sub) { Bad "Empty subdomain in response: $($s | ConvertTo-Json -Compress)" }
    $url = "https://$SCRIPT_NAME.$sub.workers.dev"

    Write-Host ""
    Write-Host "==================================================================" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Worker deployed successfully" -ForegroundColor Green
    Write-Host ""
    Write-Host "  URL:  $url" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Send this URL back to Claude — it will wire index.html"
    Write-Host "  to use this proxy instead of the inline bot token."
    Write-Host ""
    Write-Host "==================================================================" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Optional test (should return success and ping you in Telegram):"
    Write-Host ""
    Write-Host "  curl.exe -X POST $url ``"
    Write-Host "    -H `"Origin: $ALLOWED_ORIGIN`" ``"
    Write-Host "    -H `"Content-Type: application/json`" ``"
    Write-Host "    --data-raw '{\""text\"":\""Proxy deployed, hello from CLI\""}'"
    Write-Host ""
} catch { Bad "Resolve URL failed: $($_.Exception.Message)" }

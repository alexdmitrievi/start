param(
    [Parameter(Mandatory=$true)] [string]$CF_ACCOUNT,
    [Parameter(Mandatory=$true)] [string]$CF_TOKEN,
    [Parameter(Mandatory=$true)] [string]$TG_TOKEN,
    [string]$SCRIPT_NAME    = "shanset-tg-proxy",
    [string]$TG_CHAT_ID     = "407721399",
    [string]$ALLOWED_ORIGIN = "https://alexdmitrievi.github.io"
)

$ErrorActionPreference = "Continue"

$workerFile = Join-Path $PSScriptRoot "workers\telegram-proxy.js"
if (-not (Test-Path $workerFile)) {
    Write-Host "ERROR: $workerFile not found. Run from repo root." -ForegroundColor Red
    exit 1
}

$curlExe = "curl.exe"
$null = Get-Command $curlExe -ErrorAction SilentlyContinue
if (-not $?) {
    Write-Host "ERROR: curl.exe not found. Run on Windows 10/11 or install curl." -ForegroundColor Red
    exit 1
}

$api  = "https://api.cloudflare.com/client/v4"
$auth = "Authorization: Bearer $CF_TOKEN"

function Done($msg) { Write-Host "  OK: $msg" -ForegroundColor Green }
function Die($msg, $resp) {
    Write-Host "  FAIL: $msg" -ForegroundColor Red
    if ($resp) { Write-Host "  Response: $resp" -ForegroundColor DarkRed }
    exit 1
}

Write-Host ""
Write-Host "[1/5] Verify Cloudflare token" -ForegroundColor Cyan
$r = & $curlExe -sS "$api/accounts/$CF_ACCOUNT/tokens/verify" -H $auth
if ($r -notmatch '"success":true') { Die "Token verify failed" $r }
Done "Token is active"

Write-Host ""
Write-Host "[2/5] Upload Worker script ($SCRIPT_NAME)" -ForegroundColor Cyan
$meta = '{"main_module":"worker.js","compatibility_date":"2025-01-01"}'
$r = & $curlExe -sS -X PUT "$api/accounts/$CF_ACCOUNT/workers/scripts/$SCRIPT_NAME" -H $auth -F "metadata=$meta;type=application/json" -F "worker.js=@$workerFile;type=application/javascript+module;filename=worker.js"
if ($r -notmatch '"success":true') { Die "Worker upload failed" $r }
Done "Worker uploaded"

Write-Host ""
Write-Host "[3/5] Set encrypted secrets" -ForegroundColor Cyan

$body1 = '{"name":"TELEGRAM_BOT_TOKEN","text":"' + $TG_TOKEN + '","type":"secret_text"}'
$r = & $curlExe -sS -X PUT "$api/accounts/$CF_ACCOUNT/workers/scripts/$SCRIPT_NAME/secrets" -H $auth -H "Content-Type: application/json" -d $body1
if ($r -notmatch '"success":true') { Die "Secret TELEGRAM_BOT_TOKEN failed" $r }
Done "TELEGRAM_BOT_TOKEN"

$body2 = '{"name":"TELEGRAM_CHAT_ID","text":"' + $TG_CHAT_ID + '","type":"secret_text"}'
$r = & $curlExe -sS -X PUT "$api/accounts/$CF_ACCOUNT/workers/scripts/$SCRIPT_NAME/secrets" -H $auth -H "Content-Type: application/json" -d $body2
if ($r -notmatch '"success":true') { Die "Secret TELEGRAM_CHAT_ID failed" $r }
Done "TELEGRAM_CHAT_ID"

$body3 = '{"name":"ALLOWED_ORIGIN","text":"' + $ALLOWED_ORIGIN + '","type":"secret_text"}'
$r = & $curlExe -sS -X PUT "$api/accounts/$CF_ACCOUNT/workers/scripts/$SCRIPT_NAME/secrets" -H $auth -H "Content-Type: application/json" -d $body3
if ($r -notmatch '"success":true') { Die "Secret ALLOWED_ORIGIN failed" $r }
Done "ALLOWED_ORIGIN"

Write-Host ""
Write-Host "[4/5] Enable workers.dev subdomain" -ForegroundColor Cyan
$r = & $curlExe -sS -X POST "$api/accounts/$CF_ACCOUNT/workers/scripts/$SCRIPT_NAME/subdomain" -H $auth -H "Content-Type: application/json" -d '{"enabled":true,"previews_enabled":false}'
if ($r -notmatch '"success":true') { Die "Subdomain enable failed" $r }
Done "workers.dev URL enabled"

Write-Host ""
Write-Host "[5/5] Resolve URL" -ForegroundColor Cyan
$r = & $curlExe -sS "$api/accounts/$CF_ACCOUNT/workers/subdomain" -H $auth
if ($r -match '"subdomain"\s*:\s*"([^"]+)"') {
    $sub = $matches[1]
    $url = "https://$SCRIPT_NAME.$sub.workers.dev"
    Write-Host ""
    Write-Host "==================================================================" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Worker deployed successfully" -ForegroundColor Green
    Write-Host ""
    Write-Host "  URL: $url" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Send this URL back to Claude to wire index.html." -ForegroundColor White
    Write-Host ""
    Write-Host "==================================================================" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Optional test (should ping you in Telegram):"
    Write-Host ""
    Write-Host "  curl.exe -X POST $url -H `"Origin: $ALLOWED_ORIGIN`" -H `"Content-Type: application/json`" --data-raw '{\""text\"":\""Proxy deployed OK\""}'"
    Write-Host ""
} else {
    Die "Could not resolve subdomain" $r
}

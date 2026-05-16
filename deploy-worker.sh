#!/usr/bin/env bash
# Deploys the Telegram lead proxy as a Cloudflare Worker.
#
# Usage (paste your credentials inline so they never live in git):
#
#   CF_ACCOUNT="..." \
#   CF_TOKEN="..."   \
#   TG_TOKEN="..."   \
#   bash deploy-worker.sh
#
# All values can also be exported in advance:
#   export CF_ACCOUNT=... CF_TOKEN=... TG_TOKEN=...
#   bash deploy-worker.sh
#
# Optional overrides:
#   SCRIPT_NAME=shanset-tg-proxy
#   TG_CHAT_ID=407721399
#   ALLOWED_ORIGIN=https://alexdmitrievi.github.io

set -euo pipefail

: "${CF_ACCOUNT:?Set CF_ACCOUNT (Cloudflare Account ID)}"
: "${CF_TOKEN:?Set CF_TOKEN (Cloudflare API Token with Worker write scope)}"
: "${TG_TOKEN:?Set TG_TOKEN (Telegram Bot token from @BotFather)}"

SCRIPT_NAME="${SCRIPT_NAME:-shanset-tg-proxy}"
TG_CHAT_ID="${TG_CHAT_ID:-407721399}"
ALLOWED_ORIGIN="${ALLOWED_ORIGIN:-https://alexdmitrievi.github.io}"

API="https://api.cloudflare.com/client/v4"
WORKER_FILE="workers/telegram-proxy.js"

[[ -f "$WORKER_FILE" ]] || { echo "ERROR: $WORKER_FILE not found. Run from repo root." >&2; exit 1; }

step() { printf '\n\033[1;34m▸ %s\033[0m\n' "$1"; }
fail() { printf '\033[1;31m✗ %s\033[0m\n' "$1" >&2; exit 1; }
ok()   { printf '\033[1;32m✓ %s\033[0m\n' "$1"; }

step "1/5  Verify Cloudflare token"
V=$(curl -sS "${API}/accounts/${CF_ACCOUNT}/tokens/verify" -H "Authorization: Bearer ${CF_TOKEN}")
echo "$V" | grep -q '"success":true' || fail "Token verify failed: $V"
ok "Token is active"

step "2/5  Upload Worker script ($SCRIPT_NAME)"
METADATA='{"main_module":"worker.js","compatibility_date":"2025-01-01"}'
U=$(curl -sS -X PUT "${API}/accounts/${CF_ACCOUNT}/workers/scripts/${SCRIPT_NAME}" \
  -H "Authorization: Bearer ${CF_TOKEN}" \
  -F "metadata=${METADATA};type=application/json" \
  -F "worker.js=@${WORKER_FILE};type=application/javascript+module;filename=worker.js")
echo "$U" | grep -q '"success":true' || fail "Worker upload failed: $U"
ok "Worker uploaded"

step "3/5  Set encrypted secrets"
for pair in \
    "TELEGRAM_BOT_TOKEN|${TG_TOKEN}" \
    "TELEGRAM_CHAT_ID|${TG_CHAT_ID}" \
    "ALLOWED_ORIGIN|${ALLOWED_ORIGIN}"; do
  NAME="${pair%%|*}"
  VAL="${pair#*|}"
  R=$(curl -sS -X PUT "${API}/accounts/${CF_ACCOUNT}/workers/scripts/${SCRIPT_NAME}/secrets" \
    -H "Authorization: Bearer ${CF_TOKEN}" -H "Content-Type: application/json" \
    --data "{\"name\":\"${NAME}\",\"text\":\"${VAL}\",\"type\":\"secret_text\"}")
  echo "$R" | grep -q '"success":true' || fail "Secret ${NAME} failed: $R"
  ok "Secret ${NAME} set"
done

step "4/5  Enable workers.dev subdomain"
E=$(curl -sS -X POST "${API}/accounts/${CF_ACCOUNT}/workers/scripts/${SCRIPT_NAME}/subdomain" \
  -H "Authorization: Bearer ${CF_TOKEN}" -H "Content-Type: application/json" \
  --data '{"enabled":true,"previews_enabled":false}')
echo "$E" | grep -q '"success":true' || fail "Subdomain enable failed: $E"
ok "workers.dev URL enabled"

step "5/5  Resolve URL"
S=$(curl -sS "${API}/accounts/${CF_ACCOUNT}/workers/subdomain" -H "Authorization: Bearer ${CF_TOKEN}")
SUB=$(echo "$S" | python3 -c "import sys,json; print(json.load(sys.stdin)['result']['subdomain'])" 2>/dev/null || echo "")
[[ -n "$SUB" ]] || fail "Could not resolve workers.dev subdomain: $S"
WORKER_URL="https://${SCRIPT_NAME}.${SUB}.workers.dev"

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo
echo "  ✓ Worker deployed"
echo
echo "  URL:  ${WORKER_URL}"
echo
echo "  Send this URL back to Claude — it will wire index.html to use"
echo "  this proxy instead of the inline bot token."
echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo
echo "Quick test (should return {\"ok\":true} and ping you in Telegram):"
echo
echo "  curl -X POST ${WORKER_URL} \\"
echo "    -H 'Origin: ${ALLOWED_ORIGIN}' \\"
echo "    -H 'Content-Type: application/json' \\"
echo "    -d '{\"text\":\"✅ Proxy deployed, hello from CLI\"}'"
echo

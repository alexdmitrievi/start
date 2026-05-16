# Telegram Lead Proxy

Cloudflare Worker that holds your bot token server-side so it never appears in the public HTML.

## Why

Right now `index.html` contains:

```js
const TELEGRAM_BOT_TOKEN = "8940258228:...";
```

Anyone visiting the site can open DevTools → View Source → grab that token and:
- Spam your personal chat (`407721399`)
- Take over the bot (`setWebhook`)
- Read previous updates (`getUpdates`)

The proxy fixes this: the page only knows the public Worker URL; the token lives in Cloudflare encrypted variables.

## Deploy in 5 minutes

1. **Revoke the leaked token first**
   - Open Telegram → `@BotFather` → `/revoke` → pick the bot
   - Copy the new token. The old one stops working immediately.

2. **Create Worker**
   - Go to https://dash.cloudflare.com → **Workers & Pages** → **Create**
   - Choose **Create Worker** → name it `shanset-tg-proxy` → Deploy
   - Click **Edit code**, replace everything with the contents of `telegram-proxy.js`
   - Click **Save and deploy**

3. **Add encrypted variables**
   - Worker → **Settings** → **Variables and Secrets** → Add 3 variables (type: Secret):
     - `TELEGRAM_BOT_TOKEN` = new token from step 1
     - `TELEGRAM_CHAT_ID` = `407721399`
     - `ALLOWED_ORIGIN` = `https://alexdmitrievi.github.io`
   - Click **Save**

4. **Copy Worker URL**
   - It will look like `https://shanset-tg-proxy.yourname.workers.dev`

5. **Update `index.html`**
   - Find the `TELEGRAM_PROXY_URL` constant and set it to your worker URL
   - **Delete the line** with the hardcoded `TELEGRAM_BOT_TOKEN` value
   - Commit and push

That's it. The page now sends every lead through your Worker, the token is invisible to the world.

## Test it locally

```bash
curl -X POST https://shanset-tg-proxy.yourname.workers.dev \
  -H 'Origin: https://alexdmitrievi.github.io' \
  -H 'Content-Type: application/json' \
  -d '{"text":"test message"}'
```

You should see the message arrive in your Telegram.

## Costs

Cloudflare Workers free tier: **100 000 requests/day**. You will never approach this from a single landing page. Free.

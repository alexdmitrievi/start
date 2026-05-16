/**
 * Telegram Lead Proxy — Cloudflare Worker
 * Keeps TELEGRAM_BOT_TOKEN secret server-side.
 *
 * DEPLOY:
 * 1. Go to https://dash.cloudflare.com → Workers & Pages → Create
 * 2. Choose "Create Worker", name it `shanset-tg-proxy`
 * 3. Replace default code with this file's content
 * 4. Settings → Variables → Add encrypted variables:
 *      TELEGRAM_BOT_TOKEN  = your new token from BotFather (after /revoke old)
 *      TELEGRAM_CHAT_ID    = 407721399
 *      ALLOWED_ORIGIN      = https://alexdmitrievi.github.io
 * 5. Save and Deploy. Copy the worker URL (e.g. https://shanset-tg-proxy.yourname.workers.dev)
 * 6. In index.html set TELEGRAM_PROXY_URL = "<your worker URL>"
 *    Then delete the hardcoded TELEGRAM_BOT_TOKEN line
 * 7. In BotFather: /revoke → confirm — old token dies, only Worker has the new one
 */

export default {
  async fetch(request, env) {
    const origin = request.headers.get('Origin') || '';
    const allowed = env.ALLOWED_ORIGIN || '';
    const corsHeaders = {
      'Access-Control-Allow-Origin': allowed && origin === allowed ? origin : 'null',
      'Access-Control-Allow-Methods': 'POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type',
      'Access-Control-Max-Age': '86400'
    };

    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: corsHeaders });
    }
    if (request.method !== 'POST') {
      return new Response('Method not allowed', { status: 405, headers: corsHeaders });
    }
    if (!allowed || origin !== allowed) {
      return new Response('Forbidden origin', { status: 403, headers: corsHeaders });
    }

    // Naive in-memory rate limit (per worker isolate)
    // For real rate limit use Durable Objects or a KV counter
    const ip = request.headers.get('CF-Connecting-IP') || 'unknown';
    const key = `rl:${ip}`;
    globalThis.__rl ||= new Map();
    const now = Date.now();
    const bucket = globalThis.__rl.get(key) || { count: 0, reset: now + 60000 };
    if (now > bucket.reset) { bucket.count = 0; bucket.reset = now + 60000; }
    bucket.count++;
    globalThis.__rl.set(key, bucket);
    if (bucket.count > 10) {
      return new Response('Too many requests', { status: 429, headers: corsHeaders });
    }

    let payload;
    try {
      payload = await request.json();
    } catch {
      return new Response('Invalid JSON', { status: 400, headers: corsHeaders });
    }
    if (!payload || typeof payload.text !== 'string') {
      return new Response('Missing text', { status: 400, headers: corsHeaders });
    }
    if (payload.text.length > 4000) {
      return new Response('Text too long', { status: 413, headers: corsHeaders });
    }

    const token = env.TELEGRAM_BOT_TOKEN;
    const chatId = env.TELEGRAM_CHAT_ID;
    if (!token || !chatId) {
      return new Response('Server misconfigured', { status: 500, headers: corsHeaders });
    }

    const tgResp = await fetch(`https://api.telegram.org/bot${token}/sendMessage`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        chat_id: chatId,
        text: payload.text,
        disable_web_page_preview: true
      })
    });

    if (!tgResp.ok) {
      return new Response('Upstream error', { status: 502, headers: corsHeaders });
    }
    return new Response(JSON.stringify({ ok: true }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    });
  }
};

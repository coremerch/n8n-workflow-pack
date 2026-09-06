/**
 * Inbound Radar — Cloudflare Worker edition (100% free tier, no card, no server)
 * Cron every 30 min: scan n8n forum + r/n8n → keyword match → KV dedupe
 * → digest to your Discord webhook.
 * BONUS: GET https://inbound-radar.<subdomain>.workers.dev/ to force a run manually.
 *
 * Deploy:  npx wrangler deploy     (or via REST API)
 * Secret:  npx wrangler secret put DISCORD_WEBHOOK
 */
const KEYWORDS = [
  'zapier', 'make.com', 'alternativ', 'invoice', 'reminder', 'follow up', 'follow-up',
  'scrap', 'cold email', 'lead gen', 'leads', 'code node', 'self-host', 'self host',
  'selfhost', 'supabase', 'webhook', 'google sheet', 'openai', 'telegram', 'gmail', 'smtp', 'crm',
];

async function runRadar(env) {
  const seen = JSON.parse((await env.RADAR.get('seen')) || '{}');
  const matches = [];

  try {
    const f = await (await fetch('https://community.n8n.io/latest.json', {
      headers: { 'User-Agent': 'inbound-radar/1.0 (personal answer engine)' },
    })).json();
    for (const t of f.topic_list?.topics || []) {
      if (t.pinned) continue;
      const id = 'f_' + t.id;
      if (seen[id]) continue;
      const hit = KEYWORDS.find(k => (t.title || '').toLowerCase().includes(k));
      if (hit) {
        seen[id] = 1;
        matches.push({ source: 'n8n forum', title: t.title, url: `https://community.n8n.io/t/${t.slug}/${t.id}`, matched: hit });
      }
    }
  } catch (e) { /* forum down → retry next run */ }

  try {
    const r = await (await fetch('https://api.pullpush.io/reddit/search/submission/?subreddit=n8n&sort=desc&size=25', {
      headers: { 'User-Agent': 'inbound-radar/1.0 (personal answer engine)' },
    })).json();
    for (const p of r.data || []) {
      const id = 'r_' + p.id;
      if (seen[id]) continue;
      const hit = KEYWORDS.find(k => (p.title || '').toLowerCase().includes(k));
      if (hit) {
        seen[id] = 1;
        matches.push({ source: 'r/n8n', title: p.title, url: 'https://www.reddit.com' + p.permalink, matched: hit });
      }
    }
  } catch (e) { /* pullpush blocked from CF IPs sometimes → forum alone still works */ }

  if (Object.keys(seen).length > 2000) {
    for (const k of Object.keys(seen).slice(0, 1000)) delete seen[k];
  }
  await env.RADAR.put('seen', JSON.stringify(seen));

  let delivered = false;
  if (matches.length) {
    const digest = '📬 ' + matches.length + ' question(s) you can answer today:\n\n' +
      matches.map(m => `• [${m.source}] ${m.title}\n  ${m.url}  (matched: "${m.matched}")`).join('\n\n') +
      '\n\nAnswer help-first — the repo link does the pitching.';
    const res = await fetch(env.DISCORD_WEBHOOK, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ username: 'Inbound Radar (CF)', content: digest }),
    });
    delivered = res.ok;
  }
  return { count: matches.length, delivered };
}

export default {
  async scheduled(event, env, ctx) { await runRadar(env); },
  async fetch(request, env, ctx) {
    const out = await runRadar(env);
    return new Response(JSON.stringify({ ok: true, new_matches: out.count, discord_delivered: out.delivered }, null, 2),
      { headers: { 'Content-Type': 'application/json' } });
  },
};

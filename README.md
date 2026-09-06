# n8n Workflow Pack (CC0)

**Three production-shaped n8n workflows — plus a zero-infra edition of the Radar that runs *inside* Supabase (no n8n needed).**

> ⚡ **`supabase-radar.sql` is the flagship: the whole Inbound Radar as pure Postgres (`pg_cron` + `pg_net`).** Live-tested 2026-09-06: forum scan 200, Discord digest delivered (204). **In production: `cloudflare-radar/` (Worker + KV + cron, deployed via REST API — same engine, adds Reddit, runs every 30 min on Cloudflare's free tier).** Paste into the Supabase SQL editor, swap in your webhook URL, done — free tier, no server, no card.

| Workflow | What it does | The hook |
|---|---|---|
| `inbound-radar.json` | Polls r/n8n + the official n8n forum every 30 min, matches question titles against your keywords, dedupes across runs, Telegrams you a digest | **The get-chased engine.** Live-tested against the real forum — it surfaces "[For Hire]" gigs ($200–249 range) the moment they're posted |
| `invoice-chaser.json` | Reads an invoices Google Sheet daily → finds overdue rows → AI writes a reminder whose tone escalates with age (gentle → firm → final) → sends → logs | The first thing 90% of small businesses will pay for |
| `instant-lead-responder.json` | Website form POSTs → webhook → Supabase → instant AI reply with one qualifying question → owner Telegram alert | Kills the "we'll get back to you in 3 days" disease |

## Use

n8n → Workflows → **⋯ → Import from File** → pick a JSON. Each workflow has a sticky note with its exact setup checklist. Timezone pre-set to `Africa/Harare`.

```bash
git clone https://github.com/coremerch/n8n-workflow-pack.git
# or import straight from raw:
# https://raw.githubusercontent.com/coremerch/n8n-workflow-pack/main/workflows/invoice-chaser.json
```

## Requirements

- n8n self-hosted (e.g. your Render stack) or cloud
- `inbound-radar`: a Discord webhook URL only (free — Server → Channel → Integrations → Webhooks)
- `invoice-chaser`: Google Sheets + Gmail/SMTP credentials + OpenAI key
- `instant-lead-responder`: Postgres/Supabase + SMTP + Telegram + OpenAI key

**Tested**: workflow JSONs validate (nodes, connections, expression syntax); the Inbound Radar's match/dedupe/digest logic was executed against the live n8n forum API. Import and check the sticky notes before activating.

---

**Free forever · CC0** — no signup, no gate, no email wall (see `PHILOSOPHY.md`).
These saved you a weekend? **⚡ zap sats** to `SharkSkin@coinos.io`
Want them installed, customized to your stack, or one built from scratch? → **DM @your-handle** — I build automations for a living; this pack is the portfolio.

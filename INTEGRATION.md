# ClerkAI — Three-project integration

```
┌──────────────────────┐
│  apps/cler_app       │  Flutter (Android / iOS)
│  offline engine + UI │
└──────────┬───────────┘
           │ HTTPS (anon only)
     ┌─────┴──────┐
     ▼            ▼
┌─────────┐  ┌────────────────┐
│ CLER    │  │ Plan / Supabase│
│ Worker  │──│ edge functions │
│ /chat   │  │ reply_bank     │
│ /get-   │  │ pending_q      │
│  answer │  │ process-batch  │
│ /ask-   │  │ admin-review   │
│  question│  └────────────────┘
└─────────┘
```

## Turn pipeline (`IntegrationHub`)

1. **Local `processChat`** — always (scoring + patient_text / rules).
2. If **online** and `preferOnlineEngine` → optional Worker `/chat`.
3. On **miss** + online → Worker `/get-answer` → Plan `reply_bank`.
4. Still miss → Worker `/ask-question` → Plan `pending_questions` (silent queue).
5. End session → `/scores` + optional Supabase score row.

## Deploy order (Plan README)

1. Supabase migrations `001`…`006`
2. Edge functions: `ask-question`, `get-answer`, `process-batch`, `admin-review`, …
3. Secrets on Supabase (never in the app): `GEMINI_API_KEY`, `SERVICE_ROLE`, …
4. Cloudflare Worker (`backends/cler_worker`) with `SUPABASE_URL` + service role **only on Worker**
5. Flutter: set **Worker URL** + **Supabase anon key** in Settings

## Credentials

| Location | Allowed |
|----------|---------|
| Flutter app | Worker base URL, Supabase **anon** key |
| Cloudflare Worker | Supabase URL + service role, API keys |
| Supabase secrets | LLM keys, admin secret, service role |

## Modes (Settings)

| Mode | Behaviour |
|------|-----------|
| `auto` | Local engine; on miss use Plan if network up |
| `offline` | Local only |
| `online` + prefer Worker | Prefer `/chat` when reachable |

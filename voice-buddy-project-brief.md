# Project: Voice Buddy — Talking Avatar App for a 7-Year-Old

## Ground rules for whoever builds this (read first)

This is a **personal, single-user hobby project** for one family member — NOT a
production app, NOT going to app stores, NOT needing to scale past one device.

- Prioritize **small, readable, reusable code** over best practices that only
  matter at scale (no need for elaborate test suites, CI/CD pipelines, retries
  with exponential backoff, extensive logging infra, microservices, etc.)
- If a "proper" solution and a "good enough for one kid on one phone" solution
  both exist, **pick the simpler one** and say so in a code comment.
- No unnecessary dependencies, no boilerplate frameworks bolted on "just in
  case." Every library added should be justified by something this spec
  actually needs.
- Prefer a **single relay server file/small module set** over a
  heavily-layered architecture. This should be buildable and readable by one
  person in a weekend, not a team.
- Skip things not explicitly requested here (no admin dashboards, no
  multi-user support, no analytics, no i18n framework beyond the 3 languages
  named).

---

## What it is

A mobile app (Android APK) where a 7-year-old talks to an animated avatar in
real time, in Telugu, Odia, or English. The avatar acts like a friend: tells
stories, sings rhymes, has casual conversation, and remembers recent context
across sessions (short-term) plus a small set of permanent facts (long-term).

## Architecture (final, do not add extra layers)

```
Flutter APK (avatar + audio)
   |  WebSocket (raw PCM audio frames)
   v
Python relay server (Docker container on Render)
   |  WebSocket            |  Postgres connection
   v                        v
Gemini Live API          Neon Postgres (free tier, separate from Render)
```

Three deployable pieces total. Nothing else.

## 1. Frontend — Flutter APK

- Single screen. One button: **start / stop** (hold-to-talk style — audio
  only streams while pressed, not always-on mic).
- Avatar built in **Rive**, driven by a simple state machine: idle / listening
  / talking. Mouth-open amount tied to live output-audio volume (no real
  lip-sync, just volume-driven mouth states — 2-3 states is enough).
- Raw PCM audio capture/playback via a small native platform channel
  (Android `AudioRecord` / `AudioTrack`). Keep this to the minimum needed —
  no custom audio processing beyond what's required to stream PCM frames.
- Foreground service + persistent notification so it survives lock screen /
  background. Minimal implementation — just enough to keep the mic/socket
  alive, no extra features.
- Simple network check: **only allow use on Wi-Fi** (audio streaming uses
  significant data — see notes below). A basic `connectivity_plus` check is
  enough, no need for anything fancier.
- No settings screen for the child. A hidden long-press (or basic PIN) opens
  a minimal parent view: last few session summaries, a stop-app control.
  Keep this to a single simple screen, not a full dashboard.

## 2. Backend relay — Python, Dockerfile, deployed on Render

- One small `FastAPI` (or plain `websockets`) app. Responsibilities, nothing
  more:
  1. Accept the app's WebSocket connection.
  2. Open a WebSocket to Gemini Live, relay audio both directions.
  3. On session end, send the transcript to Gemini (plain text call, cheap
     flash-tier model) asking for a short summary + any new long-term facts.
  4. Read/write that summary + facts to Postgres (see schema below).
  5. On session start, pull recent summary + facts from Postgres and inject
     them into the Gemini Live system prompt.
  6. Expose a `/health` GET endpoint (returns `{"status": "ok"}`) for the
     external keep-alive pinger — no logic beyond that.
- **Do not build**: retry queues, message brokers, background job runners,
  rate limiting, multi-tenant logic. This serves one device.
- API key for Gemini lives in a Render environment variable, never in the
  APK.
- Use **`uv`** for Python environment and dependency management (not
  `pip` + `venv`, not `poetry`) — single `pyproject.toml`, lockfile via
  `uv lock`, install via `uv sync`. It's fast and keeps the whole setup to
  one tool with no separate virtualenv bookkeeping. The Dockerfile should
  install dependencies with `uv sync --frozen` rather than a `requirements.txt`
  + `pip install` step.
- System prompt should instruct the model to:
  - Speak naturally across Telugu, Odia, and English as the child does.
  - Act as a warm, friendly companion — tell stories, sing simple rhymes,
    chat casually, age-appropriate topics only.
  - If it hears something that sounds like an adult talking nearby (not
    the child), acknowledge briefly but don't treat it as the next
    conversational turn — wait for the child to speak again.
  - When generating the session summary: only summarize turns that are
    clearly part of the conversation with the child; ignore
    likely-background/adult speech fragments.

## 3. Database — Neon Postgres (free tier), separate from Render

Two small tables. Nothing more elaborate needed for one user.

```sql
create table long_term_facts (
  id serial primary key,
  fact text not null,
  created_at timestamp default now()
);

create table session_summaries (
  id serial primary key,
  summary text not null,
  created_at timestamp default now()
);
```

- Rolling window: keep only the last 3 days of rows in `session_summaries`
  (a simple `delete where created_at < now() - interval '3 days'` run at the
  end of each summarization step is enough — no need for a scheduled job
  framework).
- `long_term_facts` is small and append/update-only, never auto-purged.
- Connect via `DATABASE_URL` env var on the Render service, using
  **`asyncpg` with plain SQL strings — no ORM (no SQLAlchemy)**. With only
  two small tables and simple insert/select/delete queries, an ORM adds
  setup and abstraction this project doesn't need. A handful of small
  `async def` functions (`save_summary`, `get_recent_summaries`,
  `save_fact`, `get_facts`, `cleanup_old_summaries`) using raw SQL is the
  entire data layer.

## How the LLM connects to the database (it doesn't, directly)

Gemini never talks to Postgres. The relay does all DB work and only ever
hands Gemini plain text. Flow:

**Session start:**
1. Relay queries Neon for `long_term_facts` and recent (last 3 days)
   `session_summaries`.
2. Relay builds a plain text system prompt by string-formatting those rows
   in (e.g. "Known facts: ... Recent summary: ...").
3. Relay sends that system prompt to Gemini Live when opening the session —
   before any audio starts flowing.

**During the session:** pure audio relay between app and Gemini Live, no DB
involved.

**Session end:**
1. Relay has the full transcript (it saw every chunk pass through).
2. Relay makes a **separate plain text-generation call** to Gemini (not the
   Live/audio model — a regular cheap text model) asking for a short summary
   and any new long-term facts.
3. Relay `INSERT`s that result into `session_summaries` / `long_term_facts`.
4. Relay runs the 3-day cleanup `DELETE` on `session_summaries`.

Rough shape:

```python
async def start_session(pool, gemini_ws):
    facts = await pool.fetch("select fact from long_term_facts")
    summaries = await pool.fetch(
        "select summary from session_summaries where created_at > now() - interval '3 days'"
    )
    system_prompt = build_prompt(facts, summaries)  # plain string formatting
    await gemini_ws.send(session_config_with(system_prompt))

async def end_session(pool, transcript, gemini_text_client):
    result = await gemini_text_client.generate(
        f"Summarize and extract facts from: {transcript}"
    )
    await pool.execute(
        "insert into session_summaries (summary) values ($1)", result.summary
    )
    for fact in result.new_facts:
        await pool.execute("insert into long_term_facts (fact) values ($1)", fact)
    await pool.execute(
        "delete from session_summaries where created_at < now() - interval '3 days'"
    )
```

## Deployment notes

- Render service: Docker, Starter tier recommended for simplicity (or free
  tier + external health-check pinger hitting `/health` every 10-12 minutes
  via cron-job.org or UptimeRobot, understanding this uses most of the
  750 free instance-hours/month).
- Neon: free tier Postgres, connection string in Render env vars.
- **The Flutter frontend is NOT deployed anywhere — it is not a hosted
  service.** It is built locally into a single `.apk` file
  (`flutter build apk --release`), signed with a keystore (keep this file
  safe, needed for every future rebuild), and the resulting `.apk` file is
  sent directly to the target phone (WhatsApp/USB/Drive link) for manual
  install. There is no hosting step, no app store listing, and no ongoing
  cost for the frontend. The only thing the app needs is the Render
  backend's URL baked into its config so it knows where to open the
  WebSocket connection.

## Explicitly out of scope (do not build unless asked)

- Speaker identification / voiceprint verification (handled via soft
  prompt-based filtering instead — see system prompt notes above).
- Multi-user support, accounts, or login.
- Analytics, crash reporting, or telemetry infrastructure.
- Automated tests beyond a couple of sanity checks, if any.
- CI/CD pipelines.
- Any admin/web dashboard beyond the simple in-app parent view.

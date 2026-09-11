# Voice Buddy — Backend Relay Server

The backend relay server for **Voice Buddy (Anvi)**, an AI-powered voice companion app for a 7-year-old child.

This service bridges real-time bidirectional PCM audio between the mobile Flutter app and the **Google AI Studio Gemini Live API**, maintains short/long-term memory via **Neon Postgres**, and performs post-session conversation analysis with **Gemini Flash**.

---

## 🏗️ Architecture

```
 ┌──────────────────────┐
 │  Flutter Mobile App  │
 └──────────▲───────────┘
            │  WebSocket (16kHz in / 24kHz out raw PCM)
            ▼
 ┌────────────────────────────────────────────────────────┐
 │            Voice Buddy Relay Server (Render)           │
 │  - FastAPI WebSocket Handler & State Manager           │
 │  - Gemini Live Bidirectional Audio Bridge              │
 │  - Gemini Flash Post-Session Summarizer                │
 │  - Asyncpg Raw SQL Memory Storage                      │
 └─────────────▲────────────────────────────▲─────────────┘
               │ WebSocket                  │ asyncpg
               ▼                            ▼
 ┌───────────────────────────┐ ┌──────────────────────────┐
 │  Google AI Studio Live    │ │  Neon Postgres Database  │
 │  (gemini-2.0-flash-exp)   │ │  - long_term_facts       │
 │  - Aoede / Zephyr Voice   │ │  - session_summaries     │
 └───────────────────────────┘ └──────────────────────────┘
```

---

## 📋 Features

- **Direct Google AI Studio Connection**: Uses the Gemini Developer API (`gemini-2.0-flash-exp`) for ultra-low latency native audio dialogue.
- **Unabridged Anvi Persona**: Injects the full 768-line prompt including routines (school, spelling practice 8:30–9:00 PM, dinner, bedtime), language rules (Telugu/Odia understanding with English-first responses), and safety guardrails.
- **Automatic Memory & Rolling Summaries**:
  - `long_term_facts`: Permanent facts learned about the child (favorite color, pets, hobbies).
  - `session_summaries`: 3-day rolling window of past conversations (older summaries auto-purged).
- **Post-Session Summarization**: Calls `gemini-2.0-flash` on session disconnect to extract facts and summary (ignoring background noise/adult speech).
- **Fast & Minimal**: Managed with [`uv`](https://docs.astral.sh/uv/) and raw `asyncpg` SQL (no heavy ORM).

---

## ⚙️ Environment Variables

Create a `.env` file in the `backend/` directory (see `.env.example`):

```env
# Google AI Studio Gemini Developer API Key
GEMINI_API_KEY=your_gemini_api_key_here

# Neon Postgres Connection String (Free Tier)
DATABASE_URL=postgresql://neondb_owner:password@ep-sample.c-4.ap-southeast-1.aws.neon.tech/neondb?sslmode=require

# Server Host & Port
PORT=8000
HOST=0.0.0.0

# Gemini Models & Voice
LIVE_MODEL=gemini-2.0-flash-exp
FLASH_MODEL=gemini-2.0-flash

# Available voices: Aoede (warm female), Zephyr (youthful female), Puck (playful)
VOICE_NAME=Aoede
```

---

## 🚀 Local Development

### 1. Install Dependencies
Using `uv`:
```bash
cd backend
uv sync
```

### 2. Run Test Suite
```bash
uv run pytest
```

### 3. Start the Server
```bash
uv run uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

The server will be available at `http://localhost:8000`.

---

## 📡 API Endpoints

| Method | Endpoint | Description |
| :--- | :--- | :--- |
| `GET` | `/` | Service status and endpoint directory. |
| `GET` | `/health` | Health-check endpoint for Render / UptimeRobot keep-alive pinger. |
| `GET` | `/api/parent/data` | Returns stored facts and 3-day conversation summaries for the mobile Parent View. |
| `WS` | `/ws/audio` | Bidirectional WebSocket stream for PCM audio & state events. |

---

## 🚢 Deployment to Render

### 1. Push to GitHub
Make sure `.env` is ignored (already in `.gitignore`) and push the repository to GitHub.

### 2. Create Web Service on Render
1. In [Render Dashboard](https://dashboard.render.com/), click **New +** $\rightarrow$ **Web Service**.
2. Connect your GitHub repository.
3. Set configuration:
   - **Root Directory**: `backend`
   - **Runtime**: **Docker** (uses `backend/Dockerfile` automatically).
   - **Region**: `Singapore` (or closest region to your user).
   - **Instance Type**: `Free` (or `Starter`).
4. Add **Environment Variables**:
   - `GEMINI_API_KEY`: Your Google AI Studio API key.
   - `DATABASE_URL`: Your Neon Postgres connection string.
   - `LIVE_MODEL`: `gemini-2.0-flash-exp`
   - `FLASH_MODEL`: `gemini-2.0-flash`
   - `VOICE_NAME`: `Aoede`
5. Click **Create Web Service**.

### 3. Keep-Alive Pinger (Render Free Tier)
To prevent the free instance from sleeping after 15 minutes of inactivity:
- Set up a free monitor on [cron-job.org](https://cron-job.org/) or [uptimerobot.com](https://uptimerobot.com/) to ping `https://your-service.onrender.com/health` every **10 minutes**.

---

## 📱 Connecting the Flutter Mobile App

In `mobile/lib/config.dart`, set `backendHost` to your Render service hostname:

```dart
class AppConfig {
  static const String backendHost = 'your-service.onrender.com';
  static const bool useSecure = true; // wss:// and https://
  ...
}
```

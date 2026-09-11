import logging
from contextlib import asynccontextmanager
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
import uvicorn

from app.config import settings
from app.db import (
    create_db_pool,
    get_long_term_facts,
    get_recent_summaries,
    save_session_data,
)
from app.gemini_live import GeminiLiveRelay
from app.summarizer import summarize_session

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger("voice_buddy.main")

db_pool = None

@asynccontextmanager
async def lifespan(app: FastAPI):
    global db_pool
    logger.info("Initializing Voice Buddy Relay backend...")
    db_pool = await create_db_pool(settings.DATABASE_URL)
    yield
    if db_pool:
        await db_pool.close()
        logger.info("Database pool closed.")

app = FastAPI(title="Voice Buddy Backend Relay", lifespan=lifespan)

# Allow CORS for mobile app requests
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/")
async def root():
    """Root endpoint for status check and frontend connection info."""
    return {
        "status": "online",
        "service": "Voice Buddy Backend Relay",
        "websocket_endpoint": "/ws/audio",
        "health_endpoint": "/health",
        "parent_data_endpoint": "/api/parent/data",
    }

@app.get("/health")
async def health_check():
    """Keep-alive and health check endpoint for Render/UptimeRobot."""
    return {"status": "ok", "service": "voice-buddy-relay"}

@app.get("/api/parent/data")
async def get_parent_data():
    """Provides parent view with known long-term facts and recent session summaries."""
    facts = await get_long_term_facts(db_pool)
    summaries = await get_recent_summaries(db_pool)
    return {
        "facts": facts,
        "summaries": summaries,
    }

@app.websocket("/ws/audio")
async def audio_websocket_endpoint(websocket: WebSocket):
    """Main bidirectional audio WebSocket endpoint."""
    await websocket.accept()
    logger.info("New WebSocket connection accepted from client.")

    # 1. Fetch memory from database (or mock if db is empty)
    facts = await get_long_term_facts(db_pool)
    summaries = await get_recent_summaries(db_pool)

    # 2. Run Gemini Live audio relay
    relay = GeminiLiveRelay(
        client_ws=websocket,
        facts=facts,
        summaries=summaries,
    )

    transcript = ""
    try:
        transcript = await relay.run()
    except WebSocketDisconnect:
        logger.info("Client WebSocket disconnected cleanly.")
    except Exception as e:
        logger.error(f"Error during audio session: {e}")
    finally:
        # 3. Post-session summarization and fact extraction
        if transcript.strip():
            logger.info("Session ended with non-empty transcript. Generating summary & facts...")
            summary_result = await summarize_session(transcript)
            logger.info(f"Summary extracted: {summary_result.summary}")
            if summary_result.new_facts:
                logger.info(f"New facts learned: {summary_result.new_facts}")
            await save_session_data(
                pool=db_pool,
                summary=summary_result.summary,
                new_facts=summary_result.new_facts,
            )
        else:
            logger.info("Session ended with no transcript recorded.")

def start():
    uvicorn.run(
        "app.main:app",
        host=settings.HOST,
        port=settings.PORT,
        reload=False,
    )

if __name__ == "__main__":
    start()

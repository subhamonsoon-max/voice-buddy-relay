import logging
from typing import Optional, List
import asyncpg

logger = logging.getLogger("voice_buddy.db")

CREATE_TABLES_SQL = """
CREATE TABLE IF NOT EXISTS long_term_facts (
    id SERIAL PRIMARY KEY,
    fact TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS session_summaries (
    id SERIAL PRIMARY KEY,
    summary TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT NOW()
);
"""

async def create_db_pool(database_url: str) -> Optional[asyncpg.Pool]:
    """Initializes asyncpg pool and creates tables if they do not exist."""
    if not database_url:
        logger.warning("DATABASE_URL is not set. Running in in-memory / mock database mode.")
        return None
    try:
        pool = await asyncpg.create_pool(database_url, min_size=1, max_size=5)
        async with pool.acquire() as conn:
            await conn.execute(CREATE_TABLES_SQL)
        logger.info("Database pool connected and tables verified.")
        return pool
    except Exception as e:
        logger.error(f"Failed to connect to Postgres database: {e}")
        return None

async def get_long_term_facts(pool: Optional[asyncpg.Pool]) -> List[str]:
    """Fetch all permanent facts known about the child."""
    if not pool:
        return []
    try:
        async with pool.acquire() as conn:
            rows = await conn.fetch("SELECT fact FROM long_term_facts ORDER BY id ASC")
            return [row["fact"] for row in rows]
    except Exception as e:
        logger.error(f"Error reading long_term_facts: {e}")
        return []

async def get_recent_summaries(pool: Optional[asyncpg.Pool]) -> List[str]:
    """Fetch session summaries from the last 3 days."""
    if not pool:
        return []
    try:
        async with pool.acquire() as conn:
            rows = await conn.fetch(
                "SELECT summary FROM session_summaries WHERE created_at > NOW() - INTERVAL '3 days' ORDER BY created_at ASC"
            )
            return [row["summary"] for row in rows]
    except Exception as e:
        logger.error(f"Error reading session_summaries: {e}")
        return []

async def save_session_data(
    pool: Optional[asyncpg.Pool],
    summary: Optional[str],
    new_facts: List[str],
) -> None:
    """Save session summary and new facts, then purge summaries older than 3 days."""
    if not pool:
        logger.info(f"Mock save: summary='{summary}', facts={new_facts}")
        return

    try:
        async with pool.acquire() as conn:
            async with conn.transaction():
                if summary and summary.strip():
                    await conn.execute(
                        "INSERT INTO session_summaries (summary) VALUES ($1)",
                        summary.strip(),
                    )
                for fact in new_facts:
                    if fact and fact.strip():
                        await conn.execute(
                            "INSERT INTO long_term_facts (fact) VALUES ($1)",
                            fact.strip(),
                        )
                # Purge rolling window (> 3 days old)
                await conn.execute(
                    "DELETE FROM session_summaries WHERE created_at < NOW() - INTERVAL '3 days'"
                )
        logger.info("Saved session summary, facts, and cleaned up expired summaries.")
    except Exception as e:
        logger.error(f"Error saving session data to Postgres: {e}")

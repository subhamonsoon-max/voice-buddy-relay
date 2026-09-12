import json
import logging
from typing import List, Optional
import httpx
from pydantic import BaseModel, Field
from app.config import settings

logger = logging.getLogger("voice_buddy.summarizer")

class SessionSummaryResult(BaseModel):
    summary: str = Field(
        description="A 1-3 sentence summary of the conversation turns with the child. Ignore any background adult speech or noise."
    )
    new_facts: List[str] = Field(
        default_factory=list,
        description="List of newly learned permanent facts about the child (e.g., favorite color, pet name, sports, hobbies, friends). Empty if no new facts.",
    )

SUMMARIZER_PROMPT = """You are analyzing the transcript of a live voice conversation between a 7-year-old child and an AI friend named Anvi.

Analyze the transcript below and produce:
1. A concise 1-3 sentence summary of what the child and Anvi talked about, played, or shared.
   IMPORTANT: Focus only on the conversation with the child. Ignore any background noise, TV sounds, or stray adult speech fragments.
2. Any new long-term facts learned about the child (e.g., favorite color, favorite animal, pet names, sports played, school details, nicknames).
   Only extract stable, positive/neutral personal facts. If no new facts were learned, return an empty list.

Transcript:
{transcript}
"""

async def summarize_session(
    transcript: str,
    api_key: Optional[str] = None,
) -> SessionSummaryResult:
    """Extracts summary and facts using Groq free tier (primary and only summarizer)."""
    if not transcript or not transcript.strip():
        return SessionSummaryResult(summary="Empty session with no spoken turns.", new_facts=[])

    groq_key = settings.GROQ_API_KEY
    if not groq_key:
        logger.warning("No GROQ_API_KEY configured — skipping summarization.")
        return SessionSummaryResult(summary="Conversation completed.", new_facts=[])

    logger.info("Summarizing session with Groq...")
    prompt = SUMMARIZER_PROMPT.format(transcript=transcript)
    system_instruction = (
        "You extract conversation summaries and personal facts in JSON format. "
        "Return a JSON object with keys 'summary' (string) and 'new_facts' (list of strings)."
    )

    url = "https://api.groq.com/openai/v1/chat/completions"
    headers = {
        "Authorization": f"Bearer {groq_key}",
        "Content-Type": "application/json",
    }
    payload = {
        "model": settings.GROQ_MODEL,
        "messages": [
            {"role": "system", "content": system_instruction},
            {"role": "user", "content": prompt},
        ],
        "response_format": {"type": "json_object"},
        "temperature": 0.2,
    }

    try:
        async with httpx.AsyncClient(timeout=20.0) as client:
            resp = await client.post(url, headers=headers, json=payload)
            if resp.status_code == 200:
                data = resp.json()
                content = data["choices"][0]["message"]["content"]
                parsed = json.loads(content)
                result = SessionSummaryResult.model_validate(parsed)
                logger.info(f"Groq summary: {result.summary}")
                if result.new_facts:
                    logger.info(f"New facts learned: {result.new_facts}")
                return result
            else:
                logger.error(f"Groq API error {resp.status_code}: {resp.text}")
    except Exception as e:
        logger.error(f"Groq summarization failed: {e}")

    # Safe fallback — never crash the session
    return SessionSummaryResult(summary="Conversation completed.", new_facts=[])

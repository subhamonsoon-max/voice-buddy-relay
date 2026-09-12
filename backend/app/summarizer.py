import json
import logging
from typing import List, Optional
import httpx
from pydantic import BaseModel, Field
from google import genai
from google.genai import types
from app.config import settings

logger = logging.getLogger("voice_buddy.summarizer")

class SessionSummaryResult(BaseModel):
    summary: str = Field(
        description="A 1-3 sentence summary of the conversation turns with the child. Ignore any background adult speech or noise."
    )
    new_facts: List[str] = Field(
        default_factory=list,
        description="List of newly learned permanent facts about the child (e.g., favorite color, pet name, sports, hobbies, friends). Empty if no new facts."
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

async def summarize_with_groq(transcript: str, groq_key: str) -> Optional[SessionSummaryResult]:
    """Fallback summarizer using Groq free tier (llama-3.3-70b-versatile)."""
    logger.info("Attempting summarization with Groq fallback...")
    prompt = SUMMARIZER_PROMPT.format(transcript=transcript)
    system_instruction = "You extract conversation summaries and personal facts in JSON format. Return a JSON object with keys 'summary' (string) and 'new_facts' (list of strings)."
    
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
        async with httpx.AsyncClient(timeout=15.0) as client:
            resp = await client.post(url, headers=headers, json=payload)
            if resp.status_code == 200:
                data = resp.json()
                content = data["choices"][0]["message"]["content"]
                parsed = json.loads(content)
                logger.info("Successfully generated summary via Groq fallback.")
                return SessionSummaryResult.model_validate(parsed)
            else:
                logger.error(f"Groq API returned error {resp.status_code}: {resp.text}")
    except Exception as e:
        logger.error(f"Error calling Groq fallback: {e}")
    return None

async def summarize_session(
    transcript: str,
    api_key: Optional[str] = None,
) -> SessionSummaryResult:
    """Extracts summary and facts using Gemini 2.5 Flash with automatic Groq free fallback."""
    if not transcript or not transcript.strip():
        return SessionSummaryResult(summary="Empty session with no spoken turns.", new_facts=[])

    gemini_key = api_key or settings.GEMINI_API_KEY
    groq_key = settings.GROQ_API_KEY

    # 1. Try Primary Gemini Flash
    if gemini_key:
        try:
            client = genai.Client(api_key=gemini_key, vertexai=False)
            prompt = SUMMARIZER_PROMPT.format(transcript=transcript)

            response = await client.aio.models.generate_content(
                model=settings.FLASH_MODEL,
                contents=prompt,
                config=types.GenerateContentConfig(
                    response_mime_type="application/json",
                    response_schema=SessionSummaryResult,
                    temperature=0.2,
                ),
            )

            if response.text:
                data = json.loads(response.text)
                return SessionSummaryResult.model_validate(data)
        except Exception as e:
            logger.warning(f"Gemini Flash summarization failed/rate-limited: {e}")

    # 2. Try Fallback Groq if Gemini failed or key missing
    if groq_key:
        groq_result = await summarize_with_groq(transcript, groq_key)
        if groq_result:
            return groq_result

    # 3. Safe fallback if neither is reachable
    return SessionSummaryResult(
        summary="Conversation completed.",
        new_facts=[],
    )

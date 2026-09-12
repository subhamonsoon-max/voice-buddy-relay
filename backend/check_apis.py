import asyncio
import json
from app.config import settings
from app.db import create_db_pool, get_long_term_facts, get_recent_summaries
from app.summarizer import summarize_session, summarize_with_groq
from google import genai
from google.genai import types

async def run_all_checks():
    print("=" * 60)
    print("         VOICE BUDDY LIVE API HEALTH CHECKS         ")
    print("=" * 60)

    # 1. Check Neon Postgres
    print("\n[1/4] Testing Neon Postgres Connection...")
    try:
        pool = await create_db_pool(settings.DATABASE_URL)
        if pool:
            facts = await get_long_term_facts(pool)
            summaries = await get_recent_summaries(pool)
            await pool.close()
            print("  -> Neon Postgres: SUCCESS (Connected, tables verified)")
        else:
            print("  -> Neon Postgres: FAILED to acquire pool")
    except Exception as e:
        print("  -> Neon Postgres: ERROR:", e)

    # 2. Check Gemini Live API
    print(f"\n[2/4] Testing Google AI Studio Gemini Live ({settings.LIVE_MODEL})...")
    try:
        client = genai.Client(api_key=settings.GEMINI_API_KEY, vertexai=False)
        model_name = settings.LIVE_MODEL if settings.LIVE_MODEL.startswith("models/") else f"models/{settings.LIVE_MODEL}"
        config = types.LiveConnectConfig(
            response_modalities=[types.Modality.AUDIO],
            speech_config=types.SpeechConfig(
                voice_config=types.VoiceConfig(
                    prebuilt_voice_config=types.PrebuiltVoiceConfig(
                        voice_name=settings.VOICE_NAME
                    )
                )
            )
        )
        async with client.aio.live.connect(model=model_name, config=config) as session:
            silence = bytes(3200)
            await session.send(
                input=types.LiveClientRealtimeInput(
                    media_chunks=[types.Blob(data=silence, mime_type="audio/pcm;rate=16000")]
                )
            )
            print(f"  -> Gemini Live: SUCCESS (Connected & Audio Handshake Verified with voice '{settings.VOICE_NAME}')")
    except Exception as e:
        print("  -> Gemini Live: ERROR:", e)

    # 3. Check Primary Gemini Flash Summarizer
    print(f"\n[3/4] Testing Primary Summarizer ({settings.FLASH_MODEL})...")
    sample_transcript = "Child: Hi Anvi, I went to the zoo today with my dog Bruno and saw a giant tiger!\nAnvi: Wow, tigers are so cool! Did Bruno bark at the tiger?"
    try:
        res = await summarize_session(sample_transcript)
        print("  -> Gemini Flash: SUCCESS")
        print(f"     Summary: \"{res.summary}\"")
        print(f"     Extracted Facts: {res.new_facts}")
    except Exception as e:
        print("  -> Gemini Flash: ERROR:", e)

    # 4. Check Groq Fallback Summarizer
    print(f"\n[4/4] Testing Groq Fallback Summarizer ({settings.GROQ_MODEL})...")
    try:
        if settings.GROQ_API_KEY:
            groq_res = await summarize_with_groq(sample_transcript, settings.GROQ_API_KEY)
            if groq_res:
                print("  -> Groq Fallback: SUCCESS")
                print(f"     Summary: \"{groq_res.summary}\"")
                print(f"     Extracted Facts: {groq_res.new_facts}")
            else:
                print("  -> Groq Fallback: FAILED to parse response")
        else:
            print("  -> Groq Fallback: Skipped (No key provided)")
    except Exception as e:
        print("  -> Groq Fallback: ERROR:", e)

    print("\n" + "=" * 60)
    print("                 ALL CHECKS COMPLETED               ")
    print("=" * 60)

if __name__ == "__main__":
    asyncio.run(run_all_checks())

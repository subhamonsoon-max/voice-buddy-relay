import os
from pydantic import BaseModel
from dotenv import load_dotenv

load_dotenv(override=True)

class Settings(BaseModel):
    GEMINI_API_KEY: str = os.getenv("GEMINI_API_KEY", "")
    DATABASE_URL: str = os.getenv("DATABASE_URL", "")
    PORT: int = int(os.getenv("PORT", "8000"))
    HOST: str = os.getenv("HOST", "0.0.0.0")
    
    # Google AI Studio Gemini Live Model (Real-time Audio Dialog)
    LIVE_MODEL: str = os.getenv("LIVE_MODEL", "models/gemini-2.5-flash-native-audio-latest")
    
    # Primary Summarizer Model (Gemini Flash)
    FLASH_MODEL: str = os.getenv("FLASH_MODEL", "gemini-3.6-flash")
    
    # Optional Free Fallback Summarizer (Groq)
    GROQ_API_KEY: str = os.getenv("GROQ_API_KEY", "")
    GROQ_MODEL: str = os.getenv("GROQ_MODEL", "openai/gpt-oss-20b")
    
    VOICE_NAME: str = os.getenv("VOICE_NAME", "Aoede")  # Options: Aoede, Puck, Charon, Fenrir, Kore

settings = Settings()

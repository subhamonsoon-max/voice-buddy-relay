from datetime import datetime
import zoneinfo
from typing import List
from app.prompt_template import SYSTEM_PROMPT

def build_system_prompt(
    facts: List[str],
    summaries: List[str],
    school_discussed_today: bool = False,
    tz_name: str = "Asia/Kolkata",
) -> str:
    """Builds the complete runtime system prompt for Gemini Live using the exact persona template."""
    try:
        now = datetime.now(zoneinfo.ZoneInfo(tz_name))
    except Exception:
        now = datetime.now()

    current_datetime_str = now.strftime("%A, %B %d, %Y, %I:%M %p")

    facts_text = (
        "\n".join(f"- {f}" for f in facts) if facts else "None recorded yet."
    )
    summaries_text = (
        "\n".join(f"- {s}" for s in summaries)
        if summaries
        else "No previous conversations recorded in the last 3 days."
    )
    school_text = "Yes" if school_discussed_today else "No"

    return SYSTEM_PROMPT.format(
        current_datetime=current_datetime_str,
        facts_list=facts_text,
        recent_summaries=summaries_text,
        school_discussed_today=school_text,
    )

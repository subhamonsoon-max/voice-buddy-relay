import pytest
from app.summarizer import summarize_session, SessionSummaryResult

@pytest.mark.anyio
async def test_summarize_empty_transcript():
    res = await summarize_session("")
    assert isinstance(res, SessionSummaryResult)
    assert res.summary == "Empty session with no spoken turns."
    assert res.new_facts == []

@pytest.mark.anyio
async def test_summarize_no_api_key():
    res = await summarize_session("Child: I like playing cricket.\nAnvi: Cricket is awesome!", api_key="")
    assert isinstance(res, SessionSummaryResult)
    assert len(res.summary) > 0

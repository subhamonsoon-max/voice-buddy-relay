import pytest
from app.prompt_builder import build_system_prompt

def test_build_system_prompt_empty():
    prompt = build_system_prompt(facts=[], summaries=[])
    assert "You are Anvi" in prompt
    assert "None recorded yet." in prompt
    assert "No previous conversations recorded in the last 3 days." in prompt

def test_build_system_prompt_with_data():
    facts = ["Loves cricket", "Favorite color is blue", "Pet dog named Bruno"]
    summaries = ["Talked about school and playing cricket in the garden."]
    prompt = build_system_prompt(facts=facts, summaries=summaries, school_discussed_today=True)
    
    assert "Loves cricket" in prompt
    assert "Favorite color is blue" in prompt
    assert "Pet dog named Bruno" in prompt
    assert "Talked about school and playing cricket in the garden." in prompt
    assert "Already discussed school today:\nYes" in prompt

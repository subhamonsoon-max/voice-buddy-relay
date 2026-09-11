import pytest
from fastapi.testclient import TestClient
from app.main import app

def test_health_check():
    client = TestClient(app)
    response = client.get("/health")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "ok"
    assert data["service"] == "voice-buddy-relay"

def test_parent_data_endpoint():
    client = TestClient(app)
    response = client.get("/api/parent/data")
    assert response.status_code == 200
    data = response.json()
    assert "facts" in data
    assert "summaries" in data

import pytest
from fastapi.testclient import TestClient
from ryzen.apps.kernel_api.main import app

client = TestClient(app)

def test_health_check():
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "operational", "version": "0.1.0"}

def test_execute_action_authorized():
    payload = {
        "type": "task_execution",
        "payload": {"task": "test", "task_id": "task-123"},
        "recursion_depth": 0
    }
    response = client.post("/kernel/execute", json=payload)
    assert response.status_code == 200
    assert response.json()["status"] == "authorized"

def test_execute_action_forbidden_scope():
    payload = {
        "type": "illegal_action",
        "payload": {},
        "recursion_depth": 0
    }
    response = client.post("/kernel/execute", json=payload)
    assert response.status_code == 403
    assert "outside of authorized domain" in response.json()["detail"]

def test_execute_action_max_recursion():
    payload = {
        "type": "task_execution",
        "payload": {"task_id": "task-123"},
        "recursion_depth": 10
    }
    response = client.post("/kernel/execute", json=payload)
    assert response.status_code == 403
    assert "Max recursion depth exceeded" in response.json()["detail"]

def test_execute_action_missing_task_id():
    payload = {
        "type": "task_execution",
        "payload": {"task": "test"},
        "recursion_depth": 0
    }
    response = client.post("/kernel/execute", json=payload)
    assert response.status_code == 403
    assert "requires valid task_id" in response.json()["detail"]

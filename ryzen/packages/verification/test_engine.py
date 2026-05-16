import pytest
import asyncio
from ryzen.packages.verification.engine import RecursiveVerificationEngine

@pytest.mark.asyncio
async def test_successful_cycle():
    engine = RecursiveVerificationEngine()

    async def mock_reasoning(i): return {"plan": "do something"}
    async def mock_critique(r): return {"critique": "looks okay"}
    async def mock_validation(r, c): return {"valid": True, "data": "validated"}
    async def mock_execution(v): return {"result": "success"}

    result = await engine.execute_cycle({}, mock_reasoning, mock_critique, mock_validation, mock_execution)

    assert result["status"] == "success"
    assert "reasoning" in result
    assert "critique" in result
    assert "validation" in result
    assert "execution" in result

@pytest.mark.asyncio
async def test_failed_validation():
    engine = RecursiveVerificationEngine()

    async def mock_reasoning(i): return {"plan": "bad plan"}
    async def mock_critique(r): return {"critique": "this is bad"}
    async def mock_validation(r, c): return {"valid": False, "reason": "too risky"}
    async def mock_execution(v): return {"result": "should not run"}

    result = await engine.execute_cycle({}, mock_reasoning, mock_critique, mock_validation, mock_execution)

    assert result["status"] == "failed"
    assert result["stage"] == "validation"
    assert result["reason"] == "too risky"

@pytest.mark.asyncio
async def test_governance_failure():
    def mock_gov(v): return False
    engine = RecursiveVerificationEngine(governance_validator=mock_gov)

    async def mock_reasoning(i): return {"plan": "do something"}
    async def mock_critique(r): return {"critique": "looks okay"}
    async def mock_validation(r, c): return {"valid": True}
    async def mock_execution(v): return {"result": "success"}

    result = await engine.execute_cycle({}, mock_reasoning, mock_critique, mock_validation, mock_execution)

    assert result["status"] == "failed"
    assert result["stage"] == "governance"

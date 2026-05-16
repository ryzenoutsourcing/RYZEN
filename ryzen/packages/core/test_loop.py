import pytest
import asyncio
from unittest.mock import MagicMock, AsyncMock
from ryzen.packages.core.loop import CognitionLoop
from ryzen.packages.verification.engine import RecursiveVerificationEngine
from ryzen.apps.governance.middleware import GovernanceMiddleware
from ryzen.apps.memory.federation import MemoryFederationLayer
from ryzen.packages.brains.base import GenericBrain

@pytest.mark.asyncio
async def test_cognition_loop_success():
    # Mocks
    gov = GovernanceMiddleware(constitution="test")
    memory = MagicMock(spec=MemoryFederationLayer)
    memory.retrieve_by_layer.return_value = []
    memory.retrieve_recent.return_value = []

    verification_engine = RecursiveVerificationEngine()

    loop = CognitionLoop(gov, memory, verification_engine)

    async def mock_orchestrator(inp, ctx):
        return {"task_input": {"action": "do_test"}}

    async def mock_selector(plan):
        brain = GenericBrain(brain_id="b1", name="TestBrain", role="test")
        return brain

    result = await loop.run(
        arc_id="arc-123",
        input_data={"action": "run_test"},
        orchestrator_fn=mock_orchestrator,
        brain_selector_fn=mock_selector
    )

    assert result["status"] == "success"
    assert "trace_id" in result
    assert result["result"]["status"] == "completed"
    assert memory.store_memory.called

@pytest.mark.asyncio
async def test_cognition_loop_governance_block():
    gov = GovernanceMiddleware(constitution="test")
    memory = MagicMock(spec=MemoryFederationLayer)
    verification_engine = RecursiveVerificationEngine()

    loop = CognitionLoop(gov, memory, verification_engine)

    # Payload that triggers governance block
    input_data = {"action": "bad_action", "unrestricted_access": True}

    result = await loop.run(
        arc_id="arc-123",
        input_data=input_data,
        orchestrator_fn=AsyncMock(),
        brain_selector_fn=AsyncMock()
    )

    assert result["status"] == "governance_blocked"
    assert "governance isolation" in result["reason"]

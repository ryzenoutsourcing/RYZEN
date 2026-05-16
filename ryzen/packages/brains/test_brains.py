import pytest
import asyncio
from ryzen.packages.brains.base import GenericBrain

@pytest.mark.asyncio
async def test_generic_brain_execution():
    brain = GenericBrain(brain_id="brain-123", name="TestBrain", role="testing")
    task_input = {"action": "verify_contract"}

    result = await brain.execute(task_input)

    assert result["brain_id"] == "brain-123"
    assert result["status"] == "completed"
    assert "Processed verify_contract" in result["output"]
    assert result["metadata"]["processed_by"] == "TestBrain"

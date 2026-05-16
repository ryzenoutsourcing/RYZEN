import pytest
import asyncio
from unittest.mock import MagicMock
from ryzen.packages.core.resilience import RetryPolicy, RollbackManager
from ryzen.apps.governance.human_interface import HumanGovernanceInterface

@pytest.mark.asyncio
async def test_retry_policy():
    retry = RetryPolicy(max_retries=2, initial_delay=0.1)
    mock_func = MagicMock(side_effect=[Exception("fail"), "success"])

    # We need to wrap mock_func in a coroutine for the retry policy
    async def async_func():
        return mock_func()

    result = await retry.execute(async_func)
    assert result == "success"
    assert mock_func.call_count == 2

@pytest.mark.asyncio
async def test_rollback_manager():
    rollback = RollbackManager()
    undone = []

    async def undo_action():
        undone.append(True)

    rollback.register(undo_action)
    await rollback.rollback()
    assert len(undone) == 1

def test_human_interface():
    hi = HumanGovernanceInterface()
    aid = hi.request_approval("test", {}, "testing")
    assert not hi.is_authorized(aid)

    hi.approve(aid)
    assert hi.is_authorized(aid)

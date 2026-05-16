from abc import ABC, abstractmethod
from typing import Any, Dict
import logging

logger = logging.getLogger(__name__)

class ExecutionAdapter(ABC):
    """
    Governed real-world execution adapter.
    """

    @abstractmethod
    async def execute(self, action: str, payload: Dict[str, Any]) -> Dict[str, Any]:
        pass

class MockBookingAdapter(ExecutionAdapter):
    """
    Mock adapter for the canonical airport pickup example.
    """

    async def execute(self, action: str, payload: Dict[str, Any]) -> Dict[str, Any]:
        logger.info(f"MockBookingAdapter executing action: {action}", extra={"payload": payload})

        if action == "create_booking":
            return {
                "status": "success",
                "booking_id": "BK-999",
                "confirmation": f"Airport pickup scheduled for {payload.get('datetime')}"
            }

        return {"status": "failed", "reason": f"Unknown action: {action}"}

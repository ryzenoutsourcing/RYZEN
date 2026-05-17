from typing import Callable, Any, Dict, List, Optional
import asyncio
import logging
from enum import Enum

logger = logging.getLogger(__name__)

class FailureType(str, Enum):
    TRANSIENT = "TRANSIENT"
    ADAPTER = "ADAPTER"
    GOVERNANCE = "GOVERNANCE"
    COLLISION = "COLLISION"
    UNKNOWN = "UNKNOWN"

class RetryPolicy:
    """
    Hardened retry logic with failure classification.
    """
    def __init__(self, max_retries: int = 3, initial_delay: float = 1.0):
        self.max_retries = max_retries
        self.initial_delay = initial_delay

    async def execute(self, func: Callable, failure_type: FailureType = FailureType.TRANSIENT, *args, **kwargs) -> Any:
        # Non-retryable types
        if failure_type == FailureType.GOVERNANCE:
             logger.error("Governance failure is non-retryable.")
             return await func(*args, **kwargs)

        delay = self.initial_delay
        for attempt in range(self.max_retries):
            try:
                return await func(*args, **kwargs)
            except Exception as e:
                logger.warning(f"Execution attempt {attempt + 1} failed ({failure_type}): {str(e)}")
                if attempt == self.max_retries - 1:
                    logger.error("Max retries reached.")
                    raise e
                await asyncio.sleep(delay)
                delay *= 2

class RollbackManager:
    """
    Manages partial workflow rollbacks with consistency preservation.
    """
    def __init__(self):
        self.rollback_stack: List[Dict[str, Any]] = []

    def register(self, name: str, rollback_fn: Callable, metadata: Optional[Dict[str, Any]] = None):
        self.rollback_stack.append({
            "name": name,
            "fn": rollback_fn,
            "metadata": metadata or {}
        })

    async def rollback(self):
        logger.info(f"Initiating consistency-preserving rollback for {len(self.rollback_stack)} actions...")
        while self.rollback_stack:
            entry = self.rollback_stack.pop()
            try:
                logger.info(f"Rolling back: {entry['name']}")
                await entry['fn']()
            except Exception as e:
                logger.error(f"Rollback of {entry['name']} failed: {str(e)}")

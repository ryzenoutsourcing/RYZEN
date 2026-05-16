from typing import Callable, Any, Dict, List
import asyncio
import logging

logger = logging.getLogger(__name__)

class RetryPolicy:
    """
    Implements retry logic with exponential backoff for execution failures.
    """
    def __init__(self, max_retries: int = 3, initial_delay: float = 1.0):
        self.max_retries = max_retries
        self.initial_delay = initial_delay

    async def execute(self, func: Callable, *args, **kwargs) -> Any:
        delay = self.initial_delay
        for attempt in range(self.max_retries):
            try:
                return await func(*args, **kwargs)
            except Exception as e:
                logger.warning(f"Execution attempt {attempt + 1} failed: {str(e)}. Retrying in {delay}s...")
                if attempt == self.max_retries - 1:
                    logger.error("Max retries reached. Execution failed.")
                    raise e
                await asyncio.sleep(delay)
                delay *= 2

class RollbackManager:
    """
    Manages partial workflow rollbacks where operationally possible.
    """
    def __init__(self):
        self.rollback_stack: List[Callable] = []

    def register(self, rollback_fn: Callable):
        self.rollback_stack.append(rollback_fn)

    async def rollback(self):
        logger.info(f"Initiating rollback for {len(self.rollback_stack)} actions...")
        while self.rollback_stack:
            fn = self.rollback_stack.pop()
            try:
                await fn()
            except Exception as e:
                logger.error(f"Rollback action failed: {str(e)}")

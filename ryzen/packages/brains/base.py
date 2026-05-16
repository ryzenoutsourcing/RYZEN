from abc import ABC, abstractmethod
from typing import Any, Dict, Optional
import logging

logger = logging.getLogger(__name__)

class BaseBrain(ABC):
    """
    Standardized Brain Interface Contract.
    All brains must implement the execute method.
    """

    def __init__(self, brain_id: str, name: str, role: str, config: Optional[Dict[str, Any]] = None):
        self.brain_id = brain_id
        self.name = name
        self.role = role
        self.config = config or {}

    @abstractmethod
    async def execute(self, task_input: Dict[str, Any], context: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
        """
        Executes a specialized cognitive task.
        """
        pass

    async def coordinate(self, target_role: str, request: Dict[str, Any], loop: Any) -> Dict[str, Any]:
        """
        Explicit, traceable collaboration between brains.
        Requires the global cognition loop for orchestration.
        """
        logger.info(f"Brain {self.name} requesting coordination from role: {target_role}", extra={
            "brain_id": self.brain_id,
            "target_role": target_role,
            "request": request
        })
        # Delegation logic implemented via the loop (passed as 'loop')
        return await loop.run_delegated(target_role, request)

class GenericBrain(BaseBrain):
    """
    A concrete brain implementation for general tasks.
    """

    async def execute(self, task_input: Dict[str, Any], context: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
        logger.info(f"Brain {self.name} ({self.role}) executing task.", extra={
            "brain_id": self.brain_id,
            "task_input": task_input
        })

        # Placeholder for actual brain logic
        result = {
            "brain_id": self.brain_id,
            "status": "completed",
            "output": f"Processed {task_input.get('action', 'unknown action')}",
            "metadata": {"processed_by": self.name}
        }

        return result

from typing import Dict, Any, Optional, Set
import logging
from datetime import datetime, UTC

logger = logging.getLogger(__name__)

class ExecutionConstraints:
    """
    Production execution safety boundaries and collision detection.
    """

    def __init__(self, max_recursion: int = 5):
        self.max_recursion = max_recursion
        self.active_workflows: Set[str] = set()
        self.resource_locks: Dict[str, str] = {} # resource_id -> workflow_id

    def check_recursion(self, current_depth: int) -> Dict[str, Any]:
        if current_depth > self.max_recursion:
            logger.error(f"Recursion limit exceeded: {current_depth} > {self.max_recursion}")
            return {"valid": False, "reason": "Max recursion depth exceeded"}
        return {"valid": True}

    def check_duplicate(self, workflow_id: str) -> Dict[str, Any]:
        if workflow_id in self.active_workflows:
            logger.warning(f"Duplicate workflow detected: {workflow_id}")
            return {"valid": False, "reason": "Duplicate workflow execution prevented"}
        return {"valid": True}

    def acquire_lock(self, resource_id: str, workflow_id: str) -> Dict[str, Any]:
        """
        Collision detection: prevent concurrent mutations of the same resource.
        """
        if resource_id in self.resource_locks and self.resource_locks[resource_id] != workflow_id:
            logger.error(f"Collision detected for resource {resource_id} by workflow {workflow_id}")
            return {"valid": False, "reason": f"Resource {resource_id} is locked by another workflow"}

        self.resource_locks[resource_id] = workflow_id
        return {"valid": True}

    def release_lock(self, resource_id: str):
        if resource_id in self.resource_locks:
            del self.resource_locks[resource_id]

    def start_workflow(self, workflow_id: str):
        self.active_workflows.add(workflow_id)

    def complete_workflow(self, workflow_id: str):
        if workflow_id in self.active_workflows:
            self.active_workflows.remove(workflow_id)

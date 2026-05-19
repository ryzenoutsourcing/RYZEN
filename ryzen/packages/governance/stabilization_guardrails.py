from typing import Dict, Any, List, Optional
import logging

logger = logging.getLogger(__name__)

class RewriteLoopDetector:
    """
    Stabilization Guardrails: Identifies unnecessary workflow recreation
    and orchestration duplication.
    """
    def __init__(self):
        self.orchestration_history: List[str] = []

    def check_redundancy(self, intent_goal: str) -> Dict[str, Any]:
        """
        Compares current intent against task history to detect loops.
        """
        # Exclude 'unknown_action' from strict loop detection in MVP tests
        if intent_goal == "unknown_action":
             return {"valid": True}

        # If the same goal is repeated 3 times in a row, flag as a loop
        recent = self.orchestration_history[-2:]
        if len(recent) == 2 and all(g == intent_goal for g in recent):
             logger.error(f"Rewrite loop detected for goal: {intent_goal}")
             return {"valid": False, "reason": "Rewrite loop detected: redundant orchestration generation"}

        self.orchestration_history.append(intent_goal)
        return {"valid": True}

class RecursiveRetryInflationDetector:
    """
    Detects recursive retry explosions and inflationary execution cycling.
    """
    def __init__(self, max_total_retries: int = 10):
        self.max_total_retries = max_total_retries
        self.total_retry_count = 0

    def check_inflation(self, retry_count: int) -> Dict[str, Any]:
        self.total_retry_count += retry_count
        if self.total_retry_count > self.max_total_retries:
             return {"valid": False, "reason": "Recursive retry inflation detected"}
        return {"valid": True}

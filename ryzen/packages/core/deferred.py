from typing import Dict, Any, List, Optional
import logging
from datetime import datetime, UTC, timedelta

logger = logging.getLogger(__name__)

class RetryPatternTracker:
    def __init__(self):
        self.patterns: Dict[str, List[bool]] = {} # pattern_id -> list of success/fail

    def log_retry(self, pattern_id: str, success: bool):
        if pattern_id not in self.patterns:
            self.patterns[pattern_id] = []
        self.patterns[pattern_id].append(success)

class RecoveryArchetypeRegistry:
    def __init__(self):
        self.archetypes: Dict[str, Dict[str, Any]] = {}

    def register_archetype(self, error_type: str, recovery_strategy: Dict[str, Any]):
        self.archetypes[error_type] = recovery_strategy

class RetryScheduler:
    """
    Deferred Execution: Manages retry windows and scheduled reactivation.
    """

    def __init__(self):
        self.retry_queue: List[Dict[str, Any]] = []
        self.pattern_tracker = RetryPatternTracker()
        self.recovery_registry = RecoveryArchetypeRegistry()

    def schedule_retry(self, workflow_id: str, action_type: str, delay_seconds: int = 60):
        scheduled_time = datetime.now(UTC) + timedelta(seconds=delay_seconds)
        entry = {
            "workflow_id": workflow_id,
            "action": action_type,
            "scheduled_at": scheduled_time.isoformat(),
            "status": "pending_retry"
        }
        self.retry_queue.append(entry)
        logger.info(f"Retry scheduled for {workflow_id} at {scheduled_time}")
        return entry

    def get_ready_retries(self) -> List[Dict[str, Any]]:
        now = datetime.now(UTC).isoformat()
        ready = [r for r in self.retry_queue if r["scheduled_at"] <= now]
        self.retry_queue = [r for r in self.retry_queue if r["scheduled_at"] > now]
        return ready

from typing import Dict, Any, List, Optional
import logging
from datetime import datetime, UTC

logger = logging.getLogger(__name__)

class WorkflowTimeline:
    """
    Timeline & Lifecycle Intelligence: Tracks temporal state progression
    and lifecycle checkpoints.
    """

    def __init__(self, workflow_id: str):
        self.workflow_id = workflow_id
        self.checkpoints: List[Dict[str, Any]] = []

    def record_checkpoint(self, stage: str, status: str, metadata: Optional[Dict[str, Any]] = None):
        checkpoint = {
            "stage": stage,
            "status": status,
            "timestamp": datetime.now(UTC).isoformat(),
            "metadata": metadata or {}
        }
        self.checkpoints.append(checkpoint)
        logger.info(f"Workflow {self.workflow_id} checkpoint: {stage} ({status})")

    def get_timeline(self) -> List[Dict[str, Any]]:
        return self.checkpoints

    def get_duration_since_start(self) -> float:
        if not self.checkpoints: return 0.0
        start = datetime.fromisoformat(self.checkpoints[0]["timestamp"])
        now = datetime.now(UTC)
        return (now - start).total_seconds()

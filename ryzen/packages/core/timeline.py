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

    def analyze_lifecycle_stability(self) -> Dict[str, Any]:
        """
        Analyzes duration and escalation volatility.
        """
        if len(self.checkpoints) < 2: return {"stable": True, "reason": "Insufficient data"}

        durations = []
        for i in range(1, len(self.checkpoints)):
             start = datetime.fromisoformat(self.checkpoints[i-1]["timestamp"])
             end = datetime.fromisoformat(self.checkpoints[i]["timestamp"])
             durations.append((end - start).total_seconds())

        # Heuristic for instability: high variance in stage durations (placeholder)
        return {
            "total_duration": sum(durations),
            "stage_count": len(self.checkpoints),
            "is_unstable": any(d > 3600 for d in durations) # Example: any stage > 1hr
        }

    def get_timeline(self) -> List[Dict[str, Any]]:
        return self.checkpoints

    def get_duration_since_start(self) -> float:
        if not self.checkpoints: return 0.0
        start = datetime.fromisoformat(self.checkpoints[0]["timestamp"])
        now = datetime.now(UTC)
        return (now - start).total_seconds()

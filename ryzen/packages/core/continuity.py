from typing import Dict, Any, List, Optional
import logging
import uuid
from datetime import datetime, UTC

logger = logging.getLogger(__name__)

class WorkflowMaturityTracker:
    """
    Evaluates workflow maturity and operational reliability.
    """
    def __init__(self):
        self.workflow_stats: Dict[str, Dict[str, Any]] = {}

    def track_maturity(self, workflow_id: str, success: bool):
        if workflow_id not in self.workflow_stats:
             self.workflow_stats[workflow_id] = {"success": 0, "total": 0}

        self.workflow_stats[workflow_id]["total"] += 1
        if success:
             self.workflow_stats[workflow_id]["success"] += 1

class ContinuityStateEngine:
    """
    Ryzen Continuity State Engine: Tracks unresolved workflows, pending actions,
    and deferred operations to maintain persistent awareness.
    """

    def __init__(self, db_session=None):
        self.db = db_session
        self.unresolved_workflows: Dict[str, Dict[str, Any]] = {}
        self.deferred_records: List[Dict[str, Any]] = []

        # Phase 3.4 Stabilization Extensions
        self.maturity_tracker = WorkflowMaturityTracker()
        self.execution_stability_score: float = 1.0
        self.operational_entropy_indicator: bool = False

    def track_workflow(self, workflow_id: str, arc_id: str, state_data: Dict[str, Any]):
        """
        Logs unresolved execution chains to maintain continuity.
        """
        entry = {
            "workflow_id": workflow_id,
            "arc_id": arc_id,
            "state": state_data,
            "timestamp": datetime.now(UTC).isoformat(),
            "status": "unresolved"
        }
        self.unresolved_workflows[workflow_id] = entry
        logger.info(f"Tracking unresolved workflow: {workflow_id}", extra=entry)
        return entry

    def update_stability_metrics(self, workflow_id: str, success: bool):
        """
        Updates stability score and entropy indicator based on execution outcome.
        """
        self.maturity_tracker.track_maturity(workflow_id, success)

        # Simple heuristic for stability
        total = sum(s["total"] for s in self.maturity_tracker.workflow_stats.values())
        successes = sum(s["success"] for s in self.maturity_tracker.workflow_stats.values())

        if total > 0:
            self.execution_stability_score = round(successes / total, 2)
            self.operational_entropy_indicator = self.execution_stability_score < 0.7

    def get_deferred_records(self, arc_id: Optional[str] = None) -> List[Dict[str, Any]]:
        if arc_id:
            return [r for r in self.deferred_records if r.get("arc_id") == arc_id]
        return self.deferred_records

    def register_deferred(self, workflow_id: str, arc_id: str, reason: str, resume_at: datetime):
        record = {
            "id": str(uuid.uuid4()),
            "workflow_id": workflow_id,
            "arc_id": arc_id,
            "reason": reason,
            "resume_at": resume_at.isoformat(),
            "status": "deferred"
        }
        self.deferred_records.append(record)
        logger.info(f"Workflow {workflow_id} deferred until {record['resume_at']}: {reason}")
        return record

    def resolve_workflow(self, workflow_id: str):
        if workflow_id in self.unresolved_workflows:
            self.unresolved_workflows[workflow_id]["status"] = "resolved"
            logger.info(f"Workflow resolved: {workflow_id}")
            self.update_stability_metrics(workflow_id, True)

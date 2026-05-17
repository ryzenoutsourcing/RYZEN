from typing import Dict, Any, Optional, List
import logging
import uuid
from enum import Enum

logger = logging.getLogger(__name__)

class WorkflowStatus(str, Enum):
    ACTIVE = "ACTIVE"
    PAUSED = "PAUSED"
    STOPPED = "STOPPED"
    REJECTED = "REJECTED"

class HumanGovernanceInterface:
    """
    Hardened human operational oversight with approval queues and intervention.
    """

    def __init__(self):
        self.pending_approvals: Dict[str, Dict[str, Any]] = {}
        self.workflow_interventions: Dict[str, WorkflowStatus] = {} # workflow_id -> status

    def request_approval(self, action_type: str, payload: Dict[str, Any], reason: str) -> str:
        approval_id = str(uuid.uuid4())
        self.pending_approvals[approval_id] = {
            "id": approval_id,
            "action_type": action_type,
            "payload": payload,
            "reason": reason,
            "status": "pending",
            "timestamp": uuid.uuid4().hex # Placeholder for time
        }
        logger.info(f"Human approval requested [{approval_id}]: {reason}", extra={
            "approval_id": approval_id,
            "action_type": action_type
        })
        return approval_id

    def approve(self, approval_id: str):
        if approval_id in self.pending_approvals:
            self.pending_approvals[approval_id]["status"] = "approved"
            logger.info(f"Action approved: {approval_id}")

    def reject(self, approval_id: str):
        if approval_id in self.pending_approvals:
            self.pending_approvals[approval_id]["status"] = "rejected"
            logger.info(f"Action rejected: {approval_id}")

    def is_authorized(self, approval_id: str) -> bool:
        return self.pending_approvals.get(approval_id, {}).get("status") == "approved"

    # --- INTERVENTION METHODS ---

    def pause_workflow(self, workflow_id: str):
        self.workflow_interventions[workflow_id] = WorkflowStatus.PAUSED
        logger.warning(f"Workflow paused by human operator: {workflow_id}")

    def stop_workflow(self, workflow_id: str):
        self.workflow_interventions[workflow_id] = WorkflowStatus.STOPPED
        logger.error(f"Workflow stopped by human operator: {workflow_id}")

    def get_workflow_status(self, workflow_id: str) -> WorkflowStatus:
        return self.workflow_interventions.get(workflow_id, WorkflowStatus.ACTIVE)

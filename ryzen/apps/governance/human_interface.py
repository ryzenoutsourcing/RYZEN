from typing import Dict, Any, Optional
import logging
import uuid

logger = logging.getLogger(__name__)

class HumanGovernanceInterface:
    """
    Basic human operational oversight for high-risk actions.
    """

    def __init__(self):
        # In a real scenario, this would interact with a pending approvals DB table
        self.pending_approvals: Dict[str, Dict[str, Any]] = {}

    def request_approval(self, action_type: str, payload: Dict[str, Any], reason: str) -> str:
        approval_id = str(uuid.uuid4())
        self.pending_approvals[approval_id] = {
            "action_type": action_type,
            "payload": payload,
            "reason": reason,
            "status": "pending"
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

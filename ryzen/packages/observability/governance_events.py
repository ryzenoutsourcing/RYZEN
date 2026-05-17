from typing import Dict, Any, Optional
import logging
import json
from datetime import datetime, UTC

logger = logging.getLogger(__name__)

class GovernanceEvents:
    """
    Structured tracking of authorization, risk, and constraint events.
    """

    @staticmethod
    def log_authorization_denied(actor_role: str, action_type: str, reason: str, metadata: Optional[Dict[str, Any]] = None):
        event = {
            "event_type": "authorization_denied",
            "timestamp": datetime.now(UTC).isoformat(),
            "actor_role": actor_role,
            "action_type": action_type,
            "reason": reason,
            "metadata": metadata or {}
        }
        logger.warning(f"Governance denial: {json.dumps(event)}")

    @staticmethod
    def log_risk_escalation(action_type: str, risk_level: str, escalation_type: str, metadata: Optional[Dict[str, Any]] = None):
        event = {
            "event_type": "risk_escalation",
            "timestamp": datetime.now(UTC).isoformat(),
            "action_type": action_type,
            "risk_level": risk_level,
            "escalation_type": escalation_type,
            "metadata": metadata or {}
        }
        logger.info(f"Risk escalation triggered: {json.dumps(event)}")

    @staticmethod
    def log_constraint_violation(violation_type: str, reason: str, metadata: Optional[Dict[str, Any]] = None):
        event = {
            "event_type": "constraint_violation",
            "timestamp": datetime.now(UTC).isoformat(),
            "violation_type": violation_type,
            "reason": reason,
            "metadata": metadata or {}
        }
        logger.error(f"Execution constraint violated: {json.dumps(event)}")

from typing import Dict, Any, Optional
import logging
import json
from datetime import datetime, UTC

logger = logging.getLogger(__name__)

class ContinuityEvents:
    """
    Structured tracking of priority decisions and dependency transitions.
    """

    @staticmethod
    def log_priority_decision(workflow_id: str, action_type: str, score: float, reasoning: str):
        event = {
            "event_type": "priority_decision",
            "timestamp": datetime.now(UTC).isoformat(),
            "workflow_id": workflow_id,
            "action_type": action_type,
            "score": score,
            "reasoning": reasoning
        }
        logger.info(f"Continuity Event: {json.dumps(event)}")

    @staticmethod
    def log_dependency_transition(workflow_id: str, depends_on: str, status: str):
        event = {
            "event_type": "dependency_transition",
            "timestamp": datetime.now(UTC).isoformat(),
            "workflow_id": workflow_id,
            "depends_on": depends_on,
            "status": status
        }
        logger.info(f"Continuity Event: {json.dumps(event)}")

    @staticmethod
    def log_stability_index(workflow_id: str, stability_index: float, entropy_indicator: bool):
        event = {
            "event_type": "stability_index_update",
            "timestamp": datetime.now(UTC).isoformat(),
            "workflow_id": workflow_id,
            "stability_index": stability_index,
            "entropy_indicator": entropy_indicator
        }
        logger.info(f"Constitutional Metric Event: {json.dumps(event)}")

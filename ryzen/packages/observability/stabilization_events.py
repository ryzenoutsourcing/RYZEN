from typing import Dict, Any, Optional
import logging
import json
from datetime import datetime, UTC

logger = logging.getLogger(__name__)

class StabilizationEvents:
    """
    Structured tracking of reuse recommendations and maturity updates.
    """

    @staticmethod
    def log_pattern_maturity(pattern_id: str, score: float, metadata: Optional[Dict[str, Any]] = None):
        event = {
            "event_type": "pattern_maturity_update",
            "timestamp": datetime.now(UTC).isoformat(),
            "pattern_id": pattern_id,
            "maturity_score": score,
            "metadata": metadata or {}
        }
        logger.info(f"Stabilization Event: {json.dumps(event)}")

    @staticmethod
    def log_reuse_recommendation(workflow_id: str, pattern_id: str, reasoning: str):
        event = {
            "event_type": "reuse_recommendation",
            "timestamp": datetime.now(UTC).isoformat(),
            "workflow_id": workflow_id,
            "pattern_id": pattern_id,
            "reasoning": reasoning
        }
        logger.info(f"Stabilization Event: {json.dumps(event)}")

    @staticmethod
    def log_stabilization_metrics(workflow_id: str, reuse_ratio: float):
        event = {
            "event_type": "stabilization_metrics_update",
            "timestamp": datetime.now(UTC).isoformat(),
            "workflow_id": workflow_id,
            "reuse_ratio": reuse_ratio
        }
        logger.info(f"Constitutional Metric Event: {json.dumps(event)}")

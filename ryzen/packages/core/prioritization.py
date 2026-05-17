from typing import Dict, Any, List
import logging

logger = logging.getLogger(__name__)

class PriorityEngine:
    """
    Adaptive Prioritization Engine: Deterministically evaluates operational
    urgency and strategic weight.
    """

    def evaluate_priority(self, action_type: str, context: Dict[str, Any]) -> Dict[str, Any]:
        """
        Calculates a deterministic priority score.
        """
        urgency = 1.0 # Base urgency
        weight = 1.0 # Base strategic weight

        # Urgency factors
        if context.get("risk_level") == "CRITICAL":
            urgency += 2.0
        if context.get("is_retry"):
            urgency += 0.5

        # Strategic factors
        if action_type in ["financial_operation", "execute_booking"]:
            weight += 1.5

        priority_score = urgency * weight

        result = {
            "score": priority_score,
            "urgency": urgency,
            "strategic_weight": weight,
            "reasoning": f"Action {action_type} priority based on risk and strategic alignment"
        }

        logger.info(f"Priority evaluated for {action_type}: {priority_score}", extra=result)
        return result

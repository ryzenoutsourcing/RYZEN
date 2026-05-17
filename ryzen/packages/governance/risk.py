from enum import Enum
from typing import Dict, Any, Optional
import logging

logger = logging.getLogger(__name__)

class RiskLevel(str, Enum):
    LOW = "LOW"
    MEDIUM = "MEDIUM"
    HIGH = "HIGH"
    CRITICAL = "CRITICAL"

class RiskClassifier:
    """
    Operational action risk analysis and escalation logic.
    """

    ACTION_RISK_MAP: Dict[str, RiskLevel] = {
        "analyze_data": RiskLevel.LOW,
        "retrieve_history": RiskLevel.LOW,
        "create_booking": RiskLevel.MEDIUM,
        "update_customer": RiskLevel.MEDIUM,
        "request_schedule": RiskLevel.MEDIUM,
        "customer_reassignment": RiskLevel.HIGH,
        "update_schedule": RiskLevel.HIGH,
        "trigger_notification": RiskLevel.MEDIUM,
        "execute_booking": RiskLevel.HIGH,
        "generate_pricing": RiskLevel.MEDIUM,
        "financial_operation": RiskLevel.CRITICAL,
        "governance_override": RiskLevel.CRITICAL,
        "destructive_rollback": RiskLevel.CRITICAL
    }

    def classify(self, action_type: str) -> RiskLevel:
        return self.ACTION_RISK_MAP.get(action_type, RiskLevel.MEDIUM)

    def get_escalation_rules(self, risk_level: RiskLevel) -> Dict[str, bool]:
        """
        Defines mandatory verification requirements based on risk.
        """
        return {
            "extra_verification": risk_level in [RiskLevel.HIGH, RiskLevel.CRITICAL],
            "human_approval": risk_level == RiskLevel.CRITICAL
        }

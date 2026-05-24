from typing import Dict, Any, List, Optional
import logging
from datetime import datetime, UTC

logger = logging.getLogger(__name__)

class ConstitutionalMetrics:
    """
    Deterministic Constitutional Metrics Substrate: Hardened measurement of
    system integrity and alignment.
    """

    @staticmethod
    def calculate_context_sufficiency(context: Dict[str, Any], required_keys: List[str]) -> float:
        """
        Context Sufficiency Score: Measures the presence of required strategic context.
        """
        if not required_keys:
            return 1.0
        present = sum(1 for key in required_keys if key in context and context[key] is not None)
        return round(present / len(required_keys), 2)

    @staticmethod
    def calculate_verification_convergence(cycles: int, max_allowed: int = 3) -> float:
        """
        Recursive Verification Convergence Score: Measures efficiency of the verification cycle.
        """
        if cycles <= 1:
            return 1.0
        if cycles >= max_allowed:
            return 0.0
        return round(1.0 - ((cycles - 1) / (max_allowed - 1)), 2)

    @staticmethod
    def calculate_governance_integrity(violations: int, total_actions: int) -> float:
        """
        Governance Sequencing Integrity: Inverse of violation rate.
        """
        if total_actions == 0:
            return 1.0
        rate = violations / total_actions
        return round(max(0.0, 1.0 - rate), 2)

    @staticmethod
    def calculate_continuity_stability(success_count: int, total_count: int) -> float:
        """
        Continuity Stability Index: Success rate of workflows over time.
        """
        if total_count == 0:
            return 1.0
        return round(success_count / total_count, 2)

    @staticmethod
    def calculate_replay_integrity(original_result: Any, replay_result: Any) -> float:
        """
        Deterministic Replay Integrity: Measures consistency of replayed executions.
        """
        return 1.0 if original_result == replay_result else 0.0

    @staticmethod
    def calculate_architectural_entropy(volatility_index: float) -> bool:
        """
        Architectural Entropy Indicator: Flags high orchestration volatility.
        """
        return volatility_index > 0.5

    @staticmethod
    def calculate_stabilization_reuse(reused_count: int, total_executions: int) -> float:
        """
        Stabilization Reuse Ratio: Percentage of executions using validated archetypes.
        """
        if total_executions == 0:
            return 0.0
        return round(reused_count / total_executions, 2)

    @staticmethod
    def calculate_intent_alignment(parsed_intent: str, expected_intent: str) -> float:
        """
        Creator-Intent Alignment Proxy: Accuracy of intent parsing.
        """
        return 1.0 if parsed_intent == expected_intent else 0.0

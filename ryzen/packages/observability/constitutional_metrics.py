from typing import Dict, Any, List, Optional, Set
import logging
from datetime import datetime, UTC

logger = logging.getLogger(__name__)

class ConstitutionalMetrics:
    """
    Deterministic Constitutional Metrics Substrate: Hardened measurement of
    system integrity and alignment.
    """

    @staticmethod
    def calculate_intent_alignment(
        parsed_intent: Dict[str, Any],
        expected_intent: Dict[str, Any],
        constraints: Set[str] = None
    ) -> float:
        """
        Creator-Intent Alignment Proxy: Structured deterministic scoring dimensions.
        """
        # 1. IntentFieldCoverageScore
        parsed_keys = set(parsed_intent.get("payload", {}).keys())
        expected_keys = set(expected_intent.get("payload", {}).keys())
        if not expected_keys:
            field_coverage = 1.0
        else:
            field_coverage = len(parsed_keys.intersection(expected_keys)) / len(expected_keys)

        # 2. ActionAlignmentScore
        action_alignment = 1.0 if parsed_intent.get("intent") == expected_intent.get("intent") else 0.0

        # 3. ConstraintPreservationScore
        constraints = constraints or set()
        preserved = sum(1 for c in constraints if c in parsed_intent.get("metadata", {}))
        constraint_preservation = preserved / len(constraints) if constraints else 1.0

        # 4. ContextConsistencyScore
        # (Placeholder for complex consistency check, using simple overlap for now)
        context_consistency = 1.0 # Default

        # 5. OmissionPenalty
        omissions = expected_keys - parsed_keys
        omission_penalty = len(omissions) * 0.1

        final_score = (field_coverage * 0.4) + (action_alignment * 0.4) + (constraint_preservation * 0.2)
        final_score = max(0.0, final_score - omission_penalty)

        return round(final_score, 2)

    @staticmethod
    def calculate_context_sufficiency(
        context: Dict[str, Any],
        required_dimensions: Dict[str, List[str]]
    ) -> float:
        """
        Context Sufficiency Score: Weighted contextual significance.
        """
        weights = {
            "critical": 0.5,
            "dependency": 0.2,
            "creator": 0.2,
            "workflow": 0.1
        }

        total_score = 0.0
        for dim, keys in required_dimensions.items():
            if not keys:
                total_score += weights.get(dim, 0.0)
                continue

            present = sum(1 for key in keys if key in context and context[key] is not None)
            dim_score = present / len(keys)
            total_score += dim_score * weights.get(dim, 0.0)

        # Ambiguity Penalty (e.g. if too many None values exist in relevant keys)
        none_count = sum(1 for keys in required_dimensions.values() for key in keys if key in context and context[key] is None)
        ambiguity_penalty = none_count * 0.05

        return round(max(0.0, total_score - ambiguity_penalty), 2)

    @staticmethod
    def calculate_verification_convergence(passes: List[Dict[str, Any]]) -> float:
        """
        Recursive Verification Convergence: Multi-pass consistency comparison.
        """
        if len(passes) < 2:
            return 1.0

        # Measure consistency across validation passes
        # (Assuming passes contain 'output' or 'state' to compare)
        consistent_count = 0
        for i in range(len(passes) - 1):
            if passes[i].get("output") == passes[i+1].get("output"):
                consistent_count += 1

        convergence_stability = consistent_count / (len(passes) - 1)

        # Contradiction Detection
        # (Placeholder for deeper logic)
        contradiction_penalty = 0.0

        return round(max(0.0, convergence_stability - contradiction_penalty), 2)

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
    def calculate_replay_integrity(original_trace: List[Any], replay_trace: List[Any]) -> float:
        """
        Deterministic Replay Integrity: Validates exact replay reconstructability.
        """
        if len(original_trace) != len(replay_trace):
            return 0.0

        matches = sum(1 for o, r in zip(original_trace, replay_trace) if o == r)
        return round(matches / len(original_trace), 2)

    @staticmethod
    def calculate_architectural_entropy(
        execution_pathways: List[List[str]]
    ) -> float:
        """
        Architectural Entropy Indicator: Measurable duplicate-path / divergence analysis.
        """
        if not execution_pathways:
            return 0.0

        unique_paths = set(tuple(path) for path in execution_pathways)
        path_ratio = len(unique_paths) / len(execution_pathways)

        # Redundant execution pathways (higher ratio of duplicates -> lower entropy, but here entropy means divergence/unpredictability)
        # Actually, in this context, entropy indicates divergence/unnecessary complexity.
        # If we have many unique paths for the same goal, entropy is high.
        return round(1.0 - path_ratio, 2)

    @staticmethod
    def calculate_stabilization_reuse(reused_count: int, total_executions: int) -> float:
        """
        Stabilization Reuse Ratio: Percentage of executions using validated archetypes.
        """
        if total_executions == 0:
            return 0.0
        return round(reused_count / total_executions, 2)

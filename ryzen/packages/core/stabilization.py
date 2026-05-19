from typing import Dict, Any, List, Optional
import logging
import uuid
from datetime import datetime, UTC

logger = logging.getLogger(__name__)

class ExecutionPattern:
    def __init__(self, pattern_id: str, workflow_structure: Dict[str, Any]):
        self.pattern_id = pattern_id
        self.structure = workflow_structure
        self.success_count = 0
        self.total_count = 0
        self.last_executed = None

class PatternMaturityScore:
    @staticmethod
    def calculate(successes: int, total: int) -> float:
        if total == 0: return 0.0
        return round(successes / total, 2)

class ExecutionStabilityMetrics:
    def __init__(self):
        self.history: List[Dict[str, Any]] = []

    def log_execution(self, status: str):
        self.history.append({
            "timestamp": datetime.now(UTC).isoformat(),
            "status": status
        })

class ReusableExecutionRegistry:
    """
    Stabilization Substrate: Registry for reusable execution patterns and workflow archetypes.
    """

    def __init__(self):
        self.patterns: Dict[str, ExecutionPattern] = {}
        self.metrics: Dict[str, ExecutionStabilityMetrics] = {}

    def register_pattern(self, workflow_id: str, structure: Dict[str, Any]):
        pattern_id = str(uuid.uuid5(uuid.NAMESPACE_DNS, str(structure)))
        if pattern_id not in self.patterns:
            self.patterns[pattern_id] = ExecutionPattern(pattern_id, structure)
            self.metrics[pattern_id] = ExecutionStabilityMetrics()
        return pattern_id

    def log_result(self, pattern_id: str, success: bool):
        if pattern_id in self.patterns:
            pattern = self.patterns[pattern_id]
            pattern.total_count += 1
            if success: pattern.success_count += 1
            pattern.last_executed = datetime.now(UTC).isoformat()
            self.metrics[pattern_id].log_execution("success" if success else "failed")

    def get_maturity(self, pattern_id: str) -> float:
        if pattern_id in self.patterns:
            p = self.patterns[pattern_id]
            return PatternMaturityScore.calculate(p.success_count, p.total_count)
        return 0.0

class StabilizationRecommendation:
    def __init__(self, registry: ReusableExecutionRegistry):
        self.registry = registry

    def recommend(self, structure: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        pattern_id = str(uuid.uuid5(uuid.NAMESPACE_DNS, str(structure)))
        maturity = self.registry.get_maturity(pattern_id)
        if maturity > 0.8:
            return {
                "pattern_id": pattern_id,
                "maturity": maturity,
                "action": "reuse_validated_archetype"
            }
        return None

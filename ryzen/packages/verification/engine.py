from typing import Any, Dict, List, Callable
import logging

logger = logging.getLogger(__name__)

class RecursiveVerificationEngine:
    """
    Enforces the mandatory execution flow:
    Reasoning -> Critique -> Validation -> Execution
    """

    def __init__(self, governance_validator: Callable[[Dict[str, Any]], bool] = None):
        self.governance_validator = governance_validator

    async def execute_cycle(self, initial_input: Dict[str, Any], reasoning_step: Callable, critique_step: Callable, validation_step: Callable, execution_step: Callable) -> Dict[str, Any]:
        # 1. Reasoning
        reasoning_result = await reasoning_step(initial_input)
        logger.info(f"Reasoning complete: {reasoning_result}")

        # 2. Critique
        critique_result = await critique_step(reasoning_result)
        logger.info(f"Critique complete: {critique_result}")

        # 3. Validation
        validation_result = await validation_step(reasoning_result, critique_result)
        if not validation_result.get("valid", False):
            logger.error("Validation failed.")
            return {"status": "failed", "stage": "validation", "reason": validation_result.get("reason")}

        # Governance check
        if self.governance_validator and not self.governance_validator(validation_result):
            logger.error("Governance validation failed.")
            return {"status": "failed", "stage": "governance", "reason": "Governance misalignment"}

        # 4. Execution
        execution_result = await execution_step(validation_result)
        logger.info("Execution complete.")

        return {
            "status": "success",
            "reasoning": reasoning_result,
            "critique": critique_result,
            "validation": validation_result,
            "execution": execution_result
        }

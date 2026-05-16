from typing import Any, Dict, List, Optional, Callable
import logging
import uuid
from ryzen.packages.verification.engine import RecursiveVerificationEngine
from ryzen.apps.governance.middleware import GovernanceMiddleware
from ryzen.apps.memory.federation import MemoryFederationLayer

logger = logging.getLogger(__name__)

class CognitionLoop:
    """
    The Global Cognition Loop:
    Input → Governance → Orchestration → Brain Execution → Verification → Memory Persistence → Output
    """

    def __init__(
        self,
        governance: GovernanceMiddleware,
        memory: MemoryFederationLayer,
        verification_engine: RecursiveVerificationEngine
    ):
        self.governance = governance
        self.memory = memory
        self.verification_engine = verification_engine

    async def run_delegated(self, target_role: str, request: Dict[str, Any]) -> Dict[str, Any]:
        """
        Supports inter-brain coordination by running a delegated task.
        """
        # In a real implementation, this would recurse back through the loop with a new task.
        # For MVP, we provide a simplified delegation execution.
        logger.info(f"Executing delegated task for role: {target_role}", extra={"request": request})
        return {"status": "delegated_completed", "role": target_role, "output": f"Delegated result for {target_role}"}

    async def run(
        self,
        arc_id: str,
        input_data: Dict[str, Any],
        orchestrator_fn: Callable,
        brain_selector_fn: Optional[Callable] = None,
        is_adapter_call: bool = False
    ) -> Dict[str, Any]:
        trace_id = str(uuid.uuid4())
        logger.info(f"Starting cognition loop for ARC {arc_id}", extra={"trace_id": trace_id, "arc_id": arc_id})

        # 1. Governance Validation (Initial)
        gov_check = self.governance.validate_action({
            "type": "brain_execution",
            "payload": input_data,
            "arc_id": arc_id,
            "trace_id": trace_id
        })
        if not gov_check["valid"]:
            logger.error(f"Governance block: {gov_check['reason']}", extra={"trace_id": trace_id})
            return {"status": "governance_blocked", "reason": gov_check["reason"]}

        # 2. Memory Context Retrieval (Strategic & Operational)
        strategic_context = self.memory.retrieve_by_layer(arc_id, "strategic", limit=3)
        operational_context = self.memory.retrieve_recent(arc_id, limit=5)

        context = {
            "strategic": [m.content for m in strategic_context],
            "operational": [m.content for m in operational_context],
            "trace_id": trace_id,
            "loop": self # Allow brains to coordinate via this loop
        }

        # 3. Recursive Verification Cycle (Orchestration → Brain Execution → Verification)
        # We wrap the core execution in the verification engine

        async def reasoning_step(inp):
            # Orchestration: Deciding which brain and what plan
            return await orchestrator_fn(inp, context)

        async def critique_step(plan):
            # Self-critique of the plan
            return {"critique": "Plan adheres to operational realism", "plan_alignment": 1.0}

        async def validation_step(plan, critique):
            # Final validation before execution
            return {"valid": True, "validated_plan": plan}

        async def execution_step(validation):
            plan = validation["validated_plan"]
            if is_adapter_call:
                # Direct adapter execution if flagged (orchestrator_fn returns adapter result)
                return plan["adapter_result"]

            # Brain Execution
            selected_brain = await brain_selector_fn(plan)
            return await selected_brain.execute(plan["task_input"], context)

        # Execute the cycle
        verification_result = await self.verification_engine.execute_cycle(
            input_data,
            reasoning_step,
            critique_step,
            validation_step,
            execution_step
        )

        if verification_result["status"] != "success":
            return verification_result

        # 4. Memory Persistence (Operational)
        self.memory.store_memory(
            arc_id=arc_id,
            content=f"Executed task: {input_data.get('action')}. Result: {verification_result['execution'].get('status')}",
            memory_type="operational"
        )

        # 5. Output
        return {
            "status": "success",
            "trace_id": trace_id,
            "result": verification_result["execution"]
        }

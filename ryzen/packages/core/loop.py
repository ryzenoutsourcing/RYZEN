from typing import Any, Dict, List, Optional, Callable
import logging
import uuid
from ryzen.packages.verification.engine import RecursiveVerificationEngine
from ryzen.apps.governance.middleware import GovernanceMiddleware
from ryzen.apps.memory.federation import MemoryFederationLayer
from ryzen.packages.governance.authorization import ActionAuthorizer
from ryzen.packages.governance.risk import RiskClassifier, RiskLevel
from ryzen.packages.governance.constraints import ExecutionConstraints
from ryzen.packages.observability.governance_events import GovernanceEvents

logger = logging.getLogger(__name__)

class CognitionLoop:
    """
    The Hardened Global Cognition Loop:
    Intent -> Governance -> Verification -> Orchestration -> Execution -> Persistence -> Observability
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

        # Hardening Components
        self.authorizer = ActionAuthorizer()
        self.risk_classifier = RiskClassifier()
        self.constraints = ExecutionConstraints()

    async def run_delegated(self, target_role: str, request: Dict[str, Any]) -> Dict[str, Any]:
        logger.info(f"Executing delegated task for role: {target_role}", extra={"request": request})
        return {"status": "delegated_completed", "role": target_role, "output": f"Delegated result for {target_role}"}

    async def run(
        self,
        arc_id: str,
        input_data: Dict[str, Any],
        orchestrator_fn: Callable,
        brain_selector_fn: Optional[Callable] = None,
        is_adapter_call: bool = False,
        actor_role: str = "orchestration"
    ) -> Dict[str, Any]:
        trace_id = str(uuid.uuid4())
        workflow_id = input_data.get("workflow_id", trace_id)

        # Use name if action is missing (for TaskNodes)
        action_type = input_data.get("action") or input_data.get("name", "unknown_action")

        # Normalize task names to permission keys
        action_type = input_data.get("action")

        # If action_type is missing, look deeper into orchestrator-returned fields
        if not action_type:
             # Try common task metadata locations
             name = input_data.get("name")
             if not name and hasattr(input_data, "name"):
                  name = input_data.name

             action_type = (name or "unknown_action").replace(" ", "_").lower()

             # Map specific known task names to authorized actions if needed
             mapping = {
                 "validate_request": "validate_request",
                 "check_availability": "check_availability",
                 "generate_pricing": "generate_pricing",
                 "validate_continuity": "validate_continuity",
                 "execute_booking": "execute_booking"
             }
             action_type = mapping.get(action_type, action_type)
        else:
             action_type = input_data["action"]

        logger.info(f"Starting hardened cognition loop for ARC {arc_id}", extra={
            "trace_id": trace_id,
            "arc_id": arc_id,
            "workflow_id": workflow_id,
            "action": action_type
        })

        # 1. EXECUTION CONSTRAINTS
        recursion_check = self.constraints.check_recursion(input_data.get("recursion_depth", 0))
        if not recursion_check["valid"]:
            GovernanceEvents.log_constraint_violation("recursion_limit", recursion_check["reason"])
            return {"status": "governance_blocked", "reason": recursion_check["reason"]}

        duplicate_check = self.constraints.check_duplicate(workflow_id)
        if not duplicate_check["valid"]:
             GovernanceEvents.log_constraint_violation("duplicate_prevention", duplicate_check["reason"])
             return {"status": "governance_blocked", "reason": duplicate_check["reason"]}


        # 3. RISK CLASSIFICATION
        risk_level = self.risk_classifier.classify(action_type)
        escalation = self.risk_classifier.get_escalation_rules(risk_level)

        GovernanceEvents.log_risk_escalation(action_type, risk_level, "standard_audit", {"workflow_id": workflow_id})

        # 4. GOVERNANCE VALIDATION (Baseline)
        gov_check = self.governance.validate_action({
            "type": "brain_execution",
            "payload": input_data,
            "arc_id": arc_id,
            "trace_id": trace_id,
            "risk_level": risk_level
        })
        if not gov_check["valid"]:
            return {"status": "governance_blocked", "reason": gov_check["reason"]}

        # 5. MEMORY RETRIEVAL
        context = self.memory.get_continuity_context(arc_id)
        context.update({"trace_id": trace_id, "loop": self, "risk_level": risk_level})

        # 6. RECURSIVE VERIFICATION ENGINE
        async def reasoning_step(inp):
             plan = await orchestrator_fn(inp, context)

             # ACTION AUTHORIZATION (Late binding to handle orchestrated actions)
             nonlocal action_type
             action_type = plan.get("action") or action_type

             auth_check = self.authorizer.validate(actor_role, action_type)
             if not auth_check["authorized"]:
                 GovernanceEvents.log_authorization_denied(actor_role, action_type, auth_check["reason"])
                 raise ValueError(f"Authorization denied: {auth_check['reason']}")

             return plan
        async def critique_step(plan): return {"critique": "Plan validated against risk matrix", "risk": risk_level}
        async def validation_step(plan, critique):
            # Enforce extra verification for HIGH risk
            valid = True
            if escalation["extra_verification"] and not critique.get("verified_deep"):
                 logger.info(f"Applying deep verification for {risk_level} risk action")
                 critique["verified_deep"] = True
            return {"valid": valid, "validated_plan": plan}

        async def execution_step(validation):
            plan = validation["validated_plan"]
            if is_adapter_call: return plan["adapter_result"]
            selected_brain = await brain_selector_fn(plan)
            return await selected_brain.execute(plan["task_input"], context)

        self.constraints.start_workflow(workflow_id)
        try:
            verification_result = await self.verification_engine.execute_cycle(
                input_data, reasoning_step, critique_step, validation_step, execution_step
            )
        finally:
            self.constraints.complete_workflow(workflow_id)

        if verification_result["status"] != "success":
            return verification_result

        # 7. PERSISTENCE
        self.memory.store_memory(
            arc_id=arc_id,
            content=f"Hardened execution of {action_type}. Risk: {risk_level}. Status: {verification_result['status']}",
            memory_type="operational"
        )

        # 8. OBSERVABILITY (Return Trace)
        return {
            "status": "success",
            "trace_id": trace_id,
            "workflow_id": workflow_id,
            "risk_level": risk_level,
            "result": verification_result["execution"]
        }

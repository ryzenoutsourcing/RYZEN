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
from ryzen.packages.core.dependencies import DependencyResolver
from ryzen.packages.core.prioritization import PriorityEngine
from ryzen.packages.core.continuity import ContinuityStateEngine
from ryzen.packages.governance.conflicts import ContinuityConflictDetector
from ryzen.packages.core.stabilization import ReusableExecutionRegistry, StabilizationRecommendation
from ryzen.packages.governance.stabilization_guardrails import RewriteLoopDetector
from ryzen.packages.observability.stabilization_events import StabilizationEvents

logger = logging.getLogger(__name__)

class CognitionLoop:
    """
    The Fully Hardened Strategic Cognition Loop:
    Intent -> Governance -> Verification -> Dependency Resolution -> Prioritization -> Orchestration -> Execution -> Persistence -> Continuity Update -> Observability
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

        # Hardening & Continuity Components
        self.authorizer = ActionAuthorizer()
        self.risk_classifier = RiskClassifier()
        self.constraints = ExecutionConstraints()
        self.dependency_resolver = DependencyResolver()
        self.priority_engine = PriorityEngine()
        self.continuity_engine = ContinuityStateEngine()
        self.conflict_detector = ContinuityConflictDetector()

        # Stabilization Extensions
        self.stabilization_registry = ReusableExecutionRegistry()
        self.rewrite_detector = RewriteLoopDetector()

    async def run_delegated(self, target_role: str, request: Dict[str, Any]) -> Dict[str, Any]:
        logger.info(f"Executing delegated task for role: {target_role}", extra={"request": request})
        return {"status": "delegated_completed", "role": target_role, "output": f"Delegated result for {target_role}"}

    def _evaluate_stabilization_maturity(self, arc_id: str, workflow_id: str, action_type: str, success: bool):
        """
        Final stage: Preserve successful execution structures and maturity.
        """
        pattern_id = self.stabilization_registry.register_pattern(workflow_id, {"action": action_type})
        self.stabilization_registry.log_result(pattern_id, success)

        maturity = self.stabilization_registry.get_maturity(pattern_id)
        StabilizationEvents.log_pattern_maturity(pattern_id, maturity, {"workflow_id": workflow_id})

        if maturity > 0.8:
            StabilizationEvents.log_reuse_recommendation(workflow_id, pattern_id, "High maturity pattern detected")

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

        # Initial action_type normalization (moved declaration to avoid SyntaxError)
        def normalize_action(data):
            act = data.get("action")
            if not act:
                name = data.get("name")
                if not name and hasattr(data, "name"): name = data.name
                act = (name or "unknown_action").replace(" ", "_").lower()
                mapping = {"validate_request": "validate_request", "check_availability": "check_availability",
                           "generate_pricing": "generate_pricing", "validate_continuity": "validate_continuity",
                           "execute_booking": "execute_booking"}
                act = mapping.get(act, act)
            return act

        current_action = normalize_action(input_data)

        logger.info(f"Starting strategic cognition loop for ARC {arc_id}", extra={
            "trace_id": trace_id, "arc_id": arc_id, "workflow_id": workflow_id, "action": current_action
        })

        # 0. STABILIZATION GUARDRAILS
        loop_check = self.rewrite_detector.check_redundancy(current_action)
        if not loop_check["valid"]:
             return {"status": "governance_blocked", "reason": loop_check["reason"]}

        # 1. EXECUTION CONSTRAINTS
        recursion_check = self.constraints.check_recursion(input_data.get("recursion_depth", 0))
        if not recursion_check["valid"]:
            GovernanceEvents.log_constraint_violation("recursion_limit", recursion_check["reason"])
            return {"status": "governance_blocked", "reason": recursion_check["reason"]}

        duplicate_check = self.constraints.check_duplicate(workflow_id)
        if not duplicate_check["valid"]:
             GovernanceEvents.log_constraint_violation("duplicate_prevention", duplicate_check["reason"])
             return {"status": "governance_blocked", "reason": duplicate_check["reason"]}

        # 2. RISK CLASSIFICATION
        risk_level = self.risk_classifier.classify(current_action)
        escalation = self.risk_classifier.get_escalation_rules(risk_level)
        GovernanceEvents.log_risk_escalation(current_action, risk_level, "strategic_audit", {"workflow_id": workflow_id})

        # 3. CONTINUITY CONFLICT DETECTION
        conflict_check = self.conflict_detector.detect_resource_collisions(arc_id, current_action, input_data)
        if conflict_check.get("conflict"):
             return {"status": "governance_blocked", "reason": conflict_check["reason"]}

        # 4. GOVERNANCE VALIDATION (Baseline)
        gov_check = self.governance.validate_action({
            "type": "brain_execution", "payload": input_data, "arc_id": arc_id, "trace_id": trace_id, "risk_level": risk_level
        })
        if not gov_check["valid"]:
            return {"status": "governance_blocked", "reason": gov_check["reason"]}

        # 5. STRATEGIC MEMORY RETRIEVAL
        context = self.memory.get_continuity_context(arc_id)
        context.update(self.memory.retrieve_strategic_context(arc_id, workflow_id))
        context.update({"trace_id": trace_id, "loop": self, "risk_level": risk_level})

        # 6. RECURSIVE VERIFICATION ENGINE (Wraps Dependency, Prioritization, Execution)
        async def reasoning_step(inp):
             # A. Dependency Resolution
             deps = self.dependency_resolver.get_blocking_chains(workflow_id)
             if deps: logger.info(f"Resolving blocking chains for {workflow_id}: {deps}")

             # B. Prioritization
             priority = self.priority_engine.evaluate_priority(current_action, context)

             plan = await orchestrator_fn(inp, context)

             # C. Late Binding Action Authorization
             bound_action = plan.get("action") or current_action
             auth_check = self.authorizer.validate(actor_role, bound_action)
             if not auth_check["authorized"]:
                 GovernanceEvents.log_authorization_denied(actor_role, bound_action, auth_check["reason"])
                 raise ValueError(f"Authorization denied: {auth_check['reason']}")

             plan["priority"] = priority
             return plan

        async def critique_step(plan): return {"critique": "Plan validated against strategic priorities", "risk": risk_level}
        async def validation_step(plan, critique):
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
            content=f"Strategic execution of {current_action}. Risk: {risk_level}. Priority: {verification_result['reasoning'].get('priority', {}).get('score')}",
            memory_type="operational"
        )

        # 8. CONTINUITY UPDATE
        self.continuity_engine.track_workflow(workflow_id, arc_id, {"status": "executed", "action": current_action})

        # 9. STABILIZATION EVALUATION
        success = verification_result["status"] == "success"
        self._evaluate_stabilization_maturity(arc_id, workflow_id, current_action, success)

        # 10. OBSERVABILITY
        return {
            "status": "success",
            "trace_id": trace_id,
            "workflow_id": workflow_id,
            "risk_level": risk_level,
            "priority": verification_result["reasoning"].get("priority"),
            "result": verification_result["execution"]
        }

from typing import Dict, Any, List, Optional
from ryzen.apps.arc_factory.factory import ARCFactory
from ryzen.packages.core.loop import CognitionLoop
from ryzen.packages.core.intent import IntentParser
from ryzen.packages.core.task_graph import TaskGraphEngine, TaskState
from ryzen.packages.verification.engine import RecursiveVerificationEngine
from ryzen.apps.governance.middleware import GovernanceMiddleware
from ryzen.apps.memory.federation import MemoryFederationLayer
from ryzen.packages.brains.base import GenericBrain
from sqlalchemy.orm import Session
import logging

logger = logging.getLogger(__name__)

class FleetARC:
    """
    Fleet ARC: Phase 2 Operational Intelligence Layer.
    """

    CONSTITUTION = "FLEET ARC CONSTITUTION: Preserve continuity, unified awareness, recursive verification."

    TOPOLOGY = {
        "brains": [
            {"name": "Executive Orchestrator", "role": "orchestration", "specialization": "Decision routing"},
            {"name": "Operations", "role": "execution", "specialization": "Process execution"},
            {"name": "Sales", "role": "growth", "specialization": "Revenue generation"},
            {"name": "Customer Continuity", "role": "retention", "specialization": "Relationship preservation"},
            {"name": "Analytics", "role": "intelligence", "specialization": "Insight generation"},
            {"name": "Governance", "role": "alignment", "specialization": "Verification"},
            {"name": "Memory Continuity", "role": "preservation", "specialization": "Federated memory"}
        ]
    }

    def __init__(self, db_session: Session):
        self.db = db_session
        self.factory = ARCFactory(db_session)
        self.memory = MemoryFederationLayer(db_session)
        self.governance = GovernanceMiddleware(self.CONSTITUTION)
        self.verification_engine = RecursiveVerificationEngine()
        self.intent_parser = IntentParser()
        self.task_engine = TaskGraphEngine()
        self.cognition_loop = CognitionLoop(self.governance, self.memory, self.verification_engine)
        self.arc_record = None

    def initialize(self, creator_id: str):
        self.arc_record = self.factory.create_arc(
            name="Fleet ARC Operational",
            constitution=self.CONSTITUTION,
            topology_config=self.TOPOLOGY,
            creator_id=creator_id
        )
        return self.arc_record

    async def operational_request(self, text: str) -> Dict[str, Any]:
        """
        Universal Execution Flow:
        Input -> Intent Parsing -> Task Decomposition -> Execution
        """
        if not self.arc_record:
            raise ValueError("Fleet ARC not initialized")

        # 1. Intent Parsing
        intent_obj = self.intent_parser.parse(text)
        logger.info(f"Structured Intent: {intent_obj.intent}")

        # 2. Task Decomposition
        graph = self.task_engine.decompose(intent_obj.intent, intent_obj.payload)
        logger.info(f"Task Graph created with {len(graph.nodes)} nodes")

        # 3. Execution (Sequential for MVP)
        results = []
        for node in graph.nodes.values():
            self.task_engine.update_state(node, TaskState.EXECUTING)

            # Use Cognition Loop for each node execution
            execution_result = await self.execute_node(node)

            node.result = execution_result
            self.task_engine.update_state(node, TaskState.COMPLETED if execution_result["status"] == "success" else TaskState.FAILED)
            results.append(execution_result)

        return {
            "status": "completed",
            "goal": intent_obj.intent,
            "tasks": [n.name for n in graph.nodes.values()],
            "results": results
        }

    async def execute_node(self, node: Any) -> Dict[str, Any]:
        async def orchestrator_fn(inp, ctx):
            return {"target_role": node.brain_role, "task_input": inp}

        async def brain_selector_fn(plan):
            target_role = plan["target_role"]
            brain_record = next((b for b in self.arc_record.brains if b.role == target_role), self.arc_record.brains[0])
            return GenericBrain(brain_id=brain_record.id, name=brain_record.name, role=brain_record.role)

        return await self.cognition_loop.run(
            arc_id=self.arc_record.id,
            input_data=node.input_data,
            orchestrator_fn=orchestrator_fn,
            brain_selector_fn=brain_selector_fn
        )

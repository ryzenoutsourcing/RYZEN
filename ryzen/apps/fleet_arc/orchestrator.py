from typing import Dict, Any, List, Optional
from ryzen.apps.arc_factory.factory import ARCFactory
from ryzen.packages.core.loop import CognitionLoop
from ryzen.packages.core.intent import IntentParser
from ryzen.packages.core.task_graph import TaskGraphEngine, TaskState
from ryzen.packages.verification.engine import RecursiveVerificationEngine
from ryzen.apps.governance.middleware import GovernanceMiddleware
from ryzen.apps.memory.federation import MemoryFederationLayer
from ryzen.packages.core.booking_engine import BookingExecutionEngine
from ryzen.packages.core.scheduling import SchedulingEngine
from ryzen.packages.core.notifications import NotificationEngine
from ryzen.packages.core.adapters import CalendarAdapter, MessagingAdapter, CRMAdapter
from ryzen.packages.brains.base import GenericBrain
from sqlalchemy.orm import Session
import logging

logger = logging.getLogger(__name__)

class FleetARC:
    """
    Fleet ARC: Phase 3.1 Real Execution Infrastructure Layer.
    """

    CONSTITUTION = "FLEET ARC CONSTITUTION: Preserve continuity, unified awareness, recursive verification, operational reliability."

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

        # Real Execution Engines
        self.booking_engine = BookingExecutionEngine(db_session)
        self.scheduling_engine = SchedulingEngine(db_session)
        self.notification_engine = NotificationEngine(db_session)

        # Adapters
        self.calendar = CalendarAdapter()
        self.messaging = MessagingAdapter()
        self.crm = CRMAdapter()

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
        if not self.arc_record:
            raise ValueError("Fleet ARC not initialized")

        # 1. Intent Parsing
        intent_obj = self.intent_parser.parse(text)

        # 2. Task Decomposition
        graph = self.task_engine.decompose(intent_obj.intent, intent_obj.payload)

        # 3. Execution with Real Engines
        results = []
        for node in graph.nodes.values():
            self.task_engine.update_state(node, TaskState.EXECUTING)

            # Use Cognition Loop for each node
            execution_result = await self.execute_node(node)

            # Post-execution operational logic (simplified for MVP)
            if intent_obj.intent == "schedule_booking":
                await self.handle_booking_logic(node, execution_result)

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

    async def handle_booking_logic(self, node: Any, result: Dict[str, Any]):
        """
        Governed tool execution via the Cognition Loop.
        """
        if node.name == "Execute Booking" and result["status"] == "success":
            # 1. Governed Notification
            async def notify_orchestrator(inp, ctx):
                self.notification_engine.send_customer_notification(
                    self.arc_record.id, "cust-1", "booking_confirmed", {"details": inp}
                )
                return {"adapter_result": {"status": "notified"}}

            await self.cognition_loop.run(
                arc_id=self.arc_record.id,
                input_data=node.input_data,
                orchestrator_fn=notify_orchestrator,
                is_adapter_call=True
            )

            # 2. Governed CRM Update
            async def crm_orchestrator(inp, ctx):
                res = await self.crm.execute("update_history", {"action": "booking_created", "data": inp})
                return {"adapter_result": res}

            await self.cognition_loop.run(
                arc_id=self.arc_record.id,
                input_data=node.input_data,
                orchestrator_fn=crm_orchestrator,
                is_adapter_call=True
            )

from typing import Dict, Any, List, Optional
from ryzen.apps.arc_factory.factory import ARCFactory
from ryzen.packages.core.loop import CognitionLoop
from ryzen.packages.verification.engine import RecursiveVerificationEngine
from ryzen.apps.governance.middleware import GovernanceMiddleware
from ryzen.apps.memory.federation import MemoryFederationLayer
from ryzen.packages.brains.base import GenericBrain
from sqlalchemy.orm import Session
import logging

logger = logging.getLogger(__name__)

class FleetARC:
    """
    Fleet ARC: Real operational execution cycle.
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

    async def execute_task(self, action: str, payload: Dict[str, Any]) -> Dict[str, Any]:
        if not self.arc_record:
            raise ValueError("Fleet ARC not initialized")

        async def orchestrator_fn(inp, ctx):
            # Real routing logic: map action to role
            routing_map = {
                "sell": "growth",
                "operate": "execution",
                "analyze": "intelligence",
                "retain": "retention"
            }
            target_role = routing_map.get(inp.get("action"), "orchestration")
            return {
                "target_role": target_role,
                "task_input": inp
            }

        async def brain_selector_fn(plan):
            target_role = plan["target_role"]
            # Find the brain with the matching role in this ARC
            brain_record = next((b for b in self.arc_record.brains if b.role == target_role), self.arc_record.brains[0])
            return GenericBrain(
                brain_id=brain_record.id,
                name=brain_record.name,
                role=brain_record.role,
                config=brain_record.configuration
            )

        input_data = {"action": action, **payload}
        return await self.cognition_loop.run(
            arc_id=self.arc_record.id,
            input_data=input_data,
            orchestrator_fn=orchestrator_fn,
            brain_selector_fn=brain_selector_fn
        )

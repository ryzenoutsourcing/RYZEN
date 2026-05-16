from typing import Dict, Any, List
from ryzen.packages.schemas.models import ARC, Brain
from sqlalchemy.orm import Session
import uuid

class ARCFactory:
    """
    Generates, governs, and evolves persistent ARC ecosystems.
    """

    def __init__(self, db_session: Session):
        self.db = db_session

    def create_arc(self, name: str, constitution: str, topology_config: Dict[str, Any], creator_id: str) -> ARC:
        arc_id = str(uuid.uuid4())

        # 1. Create ARC record
        new_arc = ARC(
            id=arc_id,
            name=name,
            constitution=constitution,
            topology=topology_config,
            creator_id=creator_id,
            status="active"
        )
        self.db.add(new_arc)

        # 2. Generate Brains based on topology
        brains_config = topology_config.get("brains", [])
        for b_conf in brains_config:
            brain = Brain(
                id=str(uuid.uuid4()),
                arc_id=arc_id,
                name=b_conf["name"],
                role=b_conf["role"],
                specialization=b_conf.get("specialization"),
                governance_level=b_conf.get("governance_level", 1),
                configuration=b_conf.get("configuration", {})
            )
            self.db.add(brain)

        self.db.commit()
        self.db.refresh(new_arc)
        return new_arc

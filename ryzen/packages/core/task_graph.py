from enum import Enum
from typing import List, Dict, Any, Optional
import uuid
import logging

logger = logging.getLogger(__name__)

class TaskState(str, Enum):
    CREATED = "CREATED"
    VALIDATED = "VALIDATED"
    ASSIGNED = "ASSIGNED"
    EXECUTING = "EXECUTING"
    VERIFIED = "VERIFIED"
    PERSISTED = "PERSISTED"
    COMPLETED = "COMPLETED"
    FAILED = "FAILED"

class TaskNode:
    def __init__(self, name: str, brain_role: str, input_data: Dict[str, Any]):
        self.id = str(uuid.uuid4())
        self.name = name
        self.brain_role = brain_role
        self.input_data = input_data
        self.state = TaskState.CREATED
        self.dependencies: List[str] = [] # IDs of dependent tasks
        self.result: Optional[Dict[str, Any]] = None

class TaskGraph:
    def __init__(self, goal: str):
        self.id = str(uuid.uuid4())
        self.goal = goal
        self.nodes: Dict[str, TaskNode] = {}

    def add_node(self, node: TaskNode, depends_on: List[str] = None):
        if depends_on:
            node.dependencies = depends_on
        self.nodes[node.id] = node
        return node.id

class TaskGraphEngine:
    """
    Decomposes goals into governed subtasks and manages execution state.
    """

    def __init__(self):
        pass

    def decompose(self, intent: str, payload: Dict[str, Any]) -> TaskGraph:
        logger.info(f"Decomposing intent: {intent}")
        graph = TaskGraph(goal=intent)

        if intent == "schedule_booking":
            # 1. Validate booking request
            v_id = graph.add_node(TaskNode("Validate Request", "orchestration", payload))
            # 2. Check availability
            a_id = graph.add_node(TaskNode("Check Availability", "execution", payload), depends_on=[v_id])
            # 3. Generate pricing
            p_id = graph.add_node(TaskNode("Generate Pricing", "growth", payload), depends_on=[a_id])
            # 4. Validate customer continuity
            c_id = graph.add_node(TaskNode("Validate Continuity", "retention", payload), depends_on=[v_id])
            # 5. Execute booking
            e_id = graph.add_node(TaskNode("Execute Booking", "execution", payload), depends_on=[a_id, p_id, c_id])

            return graph

        # Default simple graph
        graph.add_node(TaskNode("Default Execution", "orchestration", payload))
        return graph

    def update_state(self, node: TaskNode, new_state: TaskState):
        logger.info(f"Task {node.id} ({node.name}) transition: {node.state} -> {new_state}")
        node.state = new_state

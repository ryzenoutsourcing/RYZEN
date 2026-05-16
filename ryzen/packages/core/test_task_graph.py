import pytest
from ryzen.packages.core.task_graph import TaskGraphEngine, TaskState

def test_task_decomposition_booking():
    engine = TaskGraphEngine()
    payload = {"pickup": "Airport"}

    graph = engine.decompose("schedule_booking", payload)

    assert graph.goal == "schedule_booking"
    assert len(graph.nodes) == 5

    # Check states and dependencies
    nodes_list = list(graph.nodes.values())
    validate_node = next(n for n in nodes_list if n.name == "Validate Request")
    assert validate_node.state == TaskState.CREATED

    execution_node = next(n for n in nodes_list if n.name == "Execute Booking")
    assert len(execution_node.dependencies) == 3

def test_task_state_transition():
    engine = TaskGraphEngine()
    graph = engine.decompose("default", {})
    node = list(graph.nodes.values())[0]

    engine.update_state(node, TaskState.EXECUTING)
    assert node.state == TaskState.EXECUTING

    engine.update_state(node, TaskState.COMPLETED)
    assert node.state == TaskState.COMPLETED

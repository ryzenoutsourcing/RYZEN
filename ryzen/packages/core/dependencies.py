from typing import Dict, List, Set, Any, Optional
import logging

logger = logging.getLogger(__name__)

class DependencyResolver:
    """
    Dependency Graph Intelligence: Manages execution dependencies,
    blocking chains, and sequencing requirements.
    """

    def __init__(self):
        self.dependencies: Dict[str, Set[str]] = {} # node_id -> set of node_ids it depends on

        # Phase 3.4 Stabilization Extensions
        self.repeated_failure_chains: List[List[str]] = []
        self.orchestration_volatility_history: List[int] = []

    def add_dependency(self, node_id: str, depends_on: str):
        if node_id not in self.dependencies:
            self.dependencies[node_id] = set()
        self.dependencies[node_id].add(depends_on)

        # Cycle Detection
        if self.has_cycle():
            self.dependencies[node_id].remove(depends_on)
            raise ValueError(f"Dependency cycle detected adding {depends_on} to {node_id}")

    def detect_unstable_chains(self, chain: List[str]):
        """
        Detects repeatedly unstable execution chains.
        """
        if chain in self.repeated_failure_chains:
             logger.warning(f"Unstable dependency chain detected: {chain}")
        self.repeated_failure_chains.append(chain)

    def calculate_volatility(self) -> float:
        """
        Calculates orchestration volatility index.
        """
        if not self.orchestration_volatility_history: return 0.0
        return sum(self.orchestration_volatility_history) / len(self.orchestration_volatility_history)

    def get_blocking_chains(self, node_id: str) -> List[str]:
        return list(self.dependencies.get(node_id, set()))

    def is_executable(self, node_id: str, completed_nodes: Set[str]) -> bool:
        deps = self.dependencies.get(node_id, set())
        return all(d in completed_nodes for d in deps)

    def has_cycle(self) -> bool:
        visited = set()
        path = set()

        def visit(n):
            if n in path: return True
            if n in visited: return False
            path.add(n)
            for neighbor in self.dependencies.get(n, set()):
                if visit(neighbor): return True
            path.remove(n)
            visited.add(n)
            return False

        for node in self.dependencies:
            if visit(node): return True
        return False

    def resolve_sequence(self, all_nodes: List[str]) -> List[str]:
        """
        Topological sort to produce execution sequence.
        """
        ordered = []
        visited = set()

        def visit(n):
            if n in visited: return
            visited.add(n)
            for d in self.dependencies.get(n, set()):
                visit(d)
            ordered.append(n)

        for node in all_nodes:
            visit(node)

        # Log volatility based on sequence length changes
        self.orchestration_volatility_history.append(len(ordered))

        return ordered

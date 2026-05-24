# CANONICAL RUNTIME PRIMITIVES

## Implemented Primitives

### Workflow
- **Module**: `ryzen/packages/core/loop.py`
- **Definition**: The top-level execution unit of the Cognition Loop.
- **Maturity**: Mature.
- **Guarantees**: Deterministic sequence of Intent -> Governance -> Verification -> Execution.

### Action
- **Module**: `ryzen/packages/governance/authorization.py`, `ryzen/packages/governance/risk.py`
- **Definition**: A specific, authorized operation mapped to a risk level.
- **Maturity**: Mature.
- **Guarantees**: Role-based access control and mandatory risk-based verification.

### Dependency Chain
- **Module**: `ryzen/packages/core/dependencies.py`
- **Definition**: A directed graph of execution requirements.
- **Maturity**: Complete.
- **Guarantees**: Cycle-free execution sequences via topological sorting.

### Constraint
- **Module**: `ryzen/packages/governance/constraints.py`
- **Definition**: Safety boundaries for execution.
- **Maturity**: Complete.
- **Guarantees**: Bounded recursion, duplicate prevention, and resource locking.

### Strategic Intent
- **Module**: `ryzen/packages/core/intent.py`
- **Definition**: Normalized representation of natural language input.
- **Maturity**: Mature.
- **Guarantees**: Deterministic mapping of text to operational goals.

### Recursive Verification Cycle
- **Module**: `ryzen/packages/verification/engine.py`
- **Definition**: Reasoning -> Critique -> Validation -> Execution pattern.
- **Maturity**: Mature.
- **Guarantees**: All non-trivial actions are audited before execution.

### Reusable Pattern (Archetype)
- **Module**: `ryzen/packages/core/stabilization.py`
- **Definition**: A validated execution structure stored for reuse.
- **Maturity**: Complete.
- **Guarantees**: Pattern ID consistency via content-hashing.

## Partially Realized Primitives

### Strategic Context
- **Module**: `ryzen/apps/memory/federation.py`
- **Definition**: The set of memories and state required for informed reasoning.
- **Current Capability**: Basic retrieval.
- **Missing Precision**: Deterministic context sufficiency scoring.

### Conflict (Resource Collision)
- **Module**: `ryzen/packages/governance/conflicts.py`
- **Definition**: Overlapping or contradictory resource assignments.
- **Current Capability**: Placeholder logic.
- **Missing Precision**: Deep scheduling integration.

## Planned-but-not-yet-materialized Primitives

### Constitutional Metric
- **Definition**: A deterministic, persisted measurement of system integrity.
- **Status**: Partially implemented across modules (e.g., `stability_score`), needs formalization.
- **Roadmap Alignment**: Phase 3.4 Operational Maturity.

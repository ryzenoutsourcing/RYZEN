# CANONICAL RUNTIME PRIMITIVES

## Strategic Intent Normalization
- **Constitutional Layer**: Intent
- **Actual Runtime Module**: `ryzen/packages/core/intent.py`
- **Inputs**: Raw natural language text, existing schema metadata.
- **Outputs**: `StructuredIntent` object (intent name, payload dict, metadata).
- **Deterministic Validation Gates**: Schema compliance check, mandatory field presence.
- **Failure Conditions**: Unrecognized intent pattern, missing critical payload fields.
- **Persistence Requirements**: Raw text and normalized intent stored in execution lineage.
- **Replay Requirements**: Identical text must yield identical `StructuredIntent` given same parser version.
- **Constitutional Invariants Enforced**: Deterministic normalization (Principle 1).

## Cognitive Task Decomposition
- **Constitutional Layer**: Orchestration
- **Actual Runtime Module**: `ryzen/packages/core/task_graph.py`
- **Inputs**: `StructuredIntent` payload, current capability map.
- **Outputs**: `TaskGraph` (nodes with assigned roles and state).
- **Deterministic Validation Gates**: DAG validation (cycle detection), role authorization check.
- **Failure Conditions**: Infinite recursion detection, unauthorized role assignment.
- **Persistence Requirements**: Graph state persisted in `TaskState` transitions.
- **Replay Requirements**: Identical intent must generate isomorphic graph structure.
- **Constitutional Invariants Enforced**: Bounded recursive decomposition (Principle 2).

## Recursive Verification Cycle
- **Constitutional Layer**: Verification
- **Actual Runtime Module**: `ryzen/packages/verification/engine.py`
- **Inputs**: Initial input data, step functions (reasoning, critique, validation, execution).
- **Outputs**: `VerificationResult` bundle (reasoning, critique, validation, execution output).
- **Deterministic Validation Gates**: Multi-pass convergence check, governance alignment gate.
- **Failure Conditions**: Critique-validation mismatch, non-convergent reasoning cycles.
- **Persistence Requirements**: Full trace of reasoning/critique persisted for audit.
- **Replay Requirements**: Deterministic step functions must yield identical trace.
- **Constitutional Invariants Enforced**: Mandatory audit before execution (Principle 4).

## Governance Action Authorization
- **Constitutional Layer**: Governance
- **Actual Runtime Module**: `ryzen/packages/governance/authorization.py`
- **Inputs**: Actor role, requested action type.
- **Outputs**: Authorization grant/denial object.
- **Deterministic Validation Gates**: Permission matrix lookup, reserved system action check.
- **Failure Conditions**: Role-action mismatch, attempted bypass of reserved actions.
- **Persistence Requirements**: Denials logged in `GovernanceEvents`.
- **Replay Requirements**: Permission matrix state must be versioned for historical replay.
- **Constitutional Invariants Enforced**: Role-based access control (Principle 2).

## Risk Classification & Escalation
- **Constitutional Layer**: Governance
- **Actual Runtime Module**: `ryzen/packages/governance/risk.py`
- **Inputs**: Action type.
- **Outputs**: `RiskLevel` (LOW to CRITICAL), escalation rules.
- **Deterministic Validation Gates**: Static risk map lookup.
- **Failure Conditions**: Unmapped action defaults to MEDIUM risk.
- **Persistence Requirements**: Risk level recorded in trace metadata.
- **Replay Requirements**: Risk map must be deterministic.
- **Constitutional Invariants Enforced**: Risk-proportional verification (Principle 3).

## Execution Safety Constraints
- **Constitutional Layer**: Governance
- **Actual Runtime Module**: `ryzen/packages/governance/constraints.py`
- **Inputs**: Current recursion depth, workflow ID, resource ID.
- **Outputs**: Safety check result (valid/invalid).
- **Deterministic Validation Gates**: Depth limit check, duplicate detection, resource lock acquisition.
- **Failure Conditions**: Max depth exceeded, duplicate execution attempt, lock collision.
- **Persistence Requirements**: Active locks and workflow registry in runtime state.
- **Replay Requirements**: Lock state must be reconstructable from event log.
- **Constitutional Invariants Enforced**: Bounded execution (Principle 2).

## Continuity State Persistence
- **Constitutional Layer**: Continuity
- **Actual Runtime Module**: `ryzen/packages/core/continuity.py`
- **Inputs**: Workflow ID, ARC ID, state data snapshot.
- **Outputs**: Unresolved workflow entry, stability update.
- **Deterministic Validation Gates**: Workflow state transition validity.
- **Failure Conditions**: Out-of-order state update, orphaned workflow detection.
- **Persistence Requirements**: Persistent storage of unresolved and deferred records.
- **Replay Requirements**: State reconstruction from chronological event stream.
- **Constitutional Invariants Enforced**: Memory and identity preservation (Principle 3).

## Dependency Resolution
- **Constitutional Layer**: Continuity
- **Actual Runtime Module**: `ryzen/packages/core/dependencies.py`
- **Inputs**: Node IDs, dependency edges.
- **Outputs**: Topologically sorted execution sequence.
- **Deterministic Validation Gates**: Cycle detection (DFS/BFS).
- **Failure Conditions**: Circular dependency detected.
- **Persistence Requirements**: Dependency graph persisted within `TaskGraph`.
- **Replay Requirements**: Stable sort ensures identical sequence for identical graph.
- **Constitutional Invariants Enforced**: Deterministic sequencing (Principle 1).

## Stabilization Pattern Registry
- **Constitutional Layer**: Stabilization
- **Actual Runtime Module**: `ryzen/packages/core/stabilization.py`
- **Inputs**: Workflow structure (dict).
- **Outputs**: Pattern ID (UUID5), maturity score.
- **Deterministic Validation Gates**: Content-hash identity check.
- **Failure Conditions**: Hash collision (statistically improbable but handled).
- **Persistence Requirements**: Registry of patterns and historical success metrics.
- **Replay Requirements**: UUID5 ensures identical ID for identical structure.
- **Constitutional Invariants Enforced**: Pattern recognition and reuse (Principle 7).

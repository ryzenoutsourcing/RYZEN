# CONSTITUTIONAL RUNTIME GAP REPORT

## Remaining Implementation Ambiguities

- **Conflict Detection Engine**: `ryzen/packages/governance/conflicts.py` still relies on simple placeholder logic. Real-world conflict detection requires deep integration with `SchedulingEngine` and `BookingExecutionEngine` state.
- **Strategic Context Sufficiency**: While the metric exists, the `CognitionLoop` does not yet block execution if the Context Sufficiency Score is below a certain threshold.
- **Deterministic Replay**: The infrastructure for "Deterministic Replay Integrity" is defined as a metric, but the actual mechanism to perform a "governed replay" of an execution trace is not fully materialized.

## Runtime Primitive Mismatches

- **Brain Specialization vs. Authorization**: Some brains in `FleetARC` have overlapping roles (e.g., `orchestration` and `alignment` both involved in verification), which might lead to ambiguity in authorization enforcement.
- **Task vs. Action**: The distinction between a "Task" (in the `TaskGraph`) and an "Action" (in the `CognitionLoop` and `ActionAuthorizer`) is mostly semantic but could be unified for better precision.

## Canon/Documentation Drift

- **Phase 3.3 Maturity**: Some components labeled as Phase 3.3 (e.g., `PriorityEngine`, `DependencyResolver`) are already complete and integrated, while others (e.g., `ContinuityConflictDetector`) are still in early stages.
- **Verification Cycle Definitions**: `AGENTS.md` and `engine.py` are aligned, but external documentation (if any) might still refer to older execution patterns.

## Repo areas needing future hardening before Phase 4

- **Governance of Adapters**: Currently, adapters like `CalendarAdapter` are called within the loop, but their internal side-effects are not fully wrapped in a recursive verification cycle.
- **Cross-ARC Continuity**: Continuity is currently tracked per `arc_id`. Phase 4 might require cross-ARC awareness and resource sharing governance.
- **Human Approval Queues**: `RiskClassifier` identifies the need for human approval for `CRITICAL` risk, but the actual async queue and intervention interface needs more operational hardening.

## Classification

| Gap | Severity | Category |
| :--- | :--- | :--- |
| Conflict Detection Reality | Critical | Runtime |
| Context Sufficiency Enforcement | Important | Governance |
| Deterministic Replay Mechanism | Future refinement | Stabilization |
| Adapter Governance | Important | Hardening |
| Cross-ARC Awareness | Future refinement | Continuity |

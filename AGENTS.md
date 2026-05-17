# Ryzen Agent Directives

## Core Principles
When working on Ryzen, adhere to these non-negotiable principles:

1. **Operational Realism**: Every implementation must be executable and production-oriented.
2. **Governance-First**: Every action must pass through governance validation.
3. **Continuity Preservation**: Preserve memory, identity, and operational history.
4. **Recursive Verification**: Follow Reasoning -> Critique -> Validation -> Execution.
5. **Modularity**: Maintain isolated responsibilities and service separation.

## Technical Constraints
- **Backend**: Python / FastAPI
- **Database**: PostgreSQL / pgvector
- **Orchestration**: LangGraph
- **Events**: Redis

## Prohibited Behaviors
- Do NOT implement uncontrolled recursive complexity or chaotic agent swarms.
- Do NOT drift into architecture without operational execution discipline.
- Avoid premature abstraction and framework addiction.

## Phase 2: Operational Intelligence Layer
1. **Structured Intent Parsing**: Deterministic normalization of input into cognition objects.
2. **Cognitive Task Graph Engine**: Bounded recursive task decomposition with explicit lifecycle states.
3. **Execution State Machine**: CREATED -> VALIDATED -> ASSIGNED -> EXECUTING -> VERIFIED -> PERSISTED -> COMPLETED.
4. **Inter-Brain Coordination**: Explicit, traceable collaboration between specialized brains.
5. **Operational Continuity**: Persistent storage for customers, bookings, and execution lineage.
6. **Tool Execution Layer**: Governed adapters for real-world actions.
7. **Enhanced Memory**: Context-aware retrieval with relevance ranking.
8. **Observability**: Execution graphs, state transitions, and coordination lineage tracing.

## Phase 3.1: Real Execution Infrastructure Layer
1. **Real Booking Execution**: Managed lifecycle (REQUESTED -> ARCHIVED) with persistent transitions.
2. **Scheduling Engine**: Driver assignment, vehicle allocation, and conflict detection logic.
3. **Notification Engine**: Customer and internal operational alerts.
4. **Execution Adapters**: Governed connectors for Calendar, Messaging, and CRM.
5. **Persistence Expansion**: Drivers, Vehicles, Schedules, and Operational Events.
6. **Human Oversight**: Manual approval flows and workflow inspection.
7. **Resilience**: Retry policies, graceful failure, and rollback infrastructure.
8. **Observability**: Real operational lineage tracking (timing, state transitions, adapter traces).

## Phase 3.2: Governance Hardening & Operational Resilience
1. **Authorization Matrix**: Brain and subsystem level permission enforcement.
2. **Risk Classification**: LOW to CRITICAL classification with mandatory escalation rules.
3. **Execution Constraints**: Recursion limits, duplicate prevention, and collision detection.
4. **Human Governance Hardening**: Approval queues and workflow intervention capabilities.
5. **Resilience Expansion**: Retry classification and failure persistence.
6. **Governance Observability**: Specialized tracking for authorization, risk, and constraint events.

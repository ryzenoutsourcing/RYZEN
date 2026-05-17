from fastapi import FastAPI, HTTPException, Request, Depends
from pydantic import BaseModel
from typing import Dict, Any, Optional, List
from ryzen.apps.governance.middleware import GovernanceMiddleware
from ryzen.apps.arc_factory.factory import ARCFactory
from ryzen.apps.fleet_arc.orchestrator import FleetARC
from ryzen.packages.schemas.models import Base, ARC, Booking, Schedule, MemoryEntry, OperationalEvent
from ryzen.packages.shared.logging import setup_logging
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, Session
from ryzen.apps.governance.human_interface import HumanGovernanceInterface

# Database setup
DATABASE_URL = "sqlite:///./ryzen.db"
engine = create_engine(DATABASE_URL, connect_args={"check_same_thread": False})
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

Base.metadata.create_all(bind=engine)

setup_logging()

app = FastAPI(title="Ryzen Kernel API")

# Singletons for MVP
human_gov = HumanGovernanceInterface()

# Dependency
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

governance = GovernanceMiddleware(constitution="Ryzen Core Constitution v1.0")

class ActionRequest(BaseModel):
    type: str
    payload: Dict[str, Any]
    recursion_depth: Optional[int] = 0

class ARCCreationRequest(BaseModel):
    name: str
    topology: Dict[str, Any]
    creator_id: str

class OperationalRequest(BaseModel):
    text: str

@app.get("/health")
async def health_check():
    return {"status": "operational", "version": "0.1.0"}

@app.post("/kernel/execute")
async def execute_action(action: ActionRequest):
    validation = governance.validate_action(action.model_dump())
    if not validation["valid"]:
        raise HTTPException(status_code=403, detail=validation["reason"])

    return {
        "status": "authorized",
        "action_type": action.type,
        "validation_metadata": validation
    }

@app.post("/arcs/create")
async def create_arc(request: ARCCreationRequest, db: Session = Depends(get_db)):
    factory = ARCFactory(db)
    arc = factory.create_arc(
        name=request.name,
        constitution="Standard ARC Constitution",
        topology_config=request.topology,
        creator_id=request.creator_id
    )
    return {"status": "created", "arc_id": arc.id, "name": arc.name}

@app.post("/fleet/initialize")
async def initialize_fleet(creator_id: str, db: Session = Depends(get_db)):
    fleet = FleetARC(db)
    arc = fleet.initialize(creator_id=creator_id)
    return {"status": "initialized", "arc_id": arc.id, "brain_count": len(arc.brains)}

@app.post("/fleet/request")
async def handle_operational_request(request: OperationalRequest, db: Session = Depends(get_db)):
    arc_record = db.query(ARC).filter(ARC.name == "Fleet ARC Operational").first()
    if not arc_record:
        raise HTTPException(status_code=404, detail="Fleet ARC not initialized.")

    fleet = FleetARC(db)
    fleet.arc_record = arc_record
    result = await fleet.operational_request(request.text)
    return result

# --- PHASE 3.2 EXPANDED ENDPOINTS ---

@app.get("/governance/approvals")
async def list_pending_approvals():
    return list(human_gov.pending_approvals.values())

@app.post("/governance/approve/{approval_id}")
async def approve_action(approval_id: str):
    human_gov.approve(approval_id)
    return {"status": "approved", "id": approval_id}

@app.get("/governance/audits")
async def get_governance_audits(db: Session = Depends(get_db)):
    return db.query(MemoryEntry).filter(MemoryEntry.memory_type == "governance").all()

@app.get("/resilience/history")
async def get_resilience_history(db: Session = Depends(get_db)):
    return db.query(OperationalEvent).filter(OperationalEvent.event_type.in_(["failure", "state_transition"])).all()

# --- EXISTING ENDPOINTS ---

@app.get("/bookings")
async def list_bookings(db: Session = Depends(get_db)):
    return db.query(Booking).all()

@app.get("/schedules")
async def list_schedules(db: Session = Depends(get_db)):
    return db.query(Schedule).all()

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)

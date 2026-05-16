from fastapi import FastAPI, HTTPException, Request, Depends
from pydantic import BaseModel
from typing import Dict, Any, Optional, List
from ryzen.apps.governance.middleware import GovernanceMiddleware
from ryzen.apps.arc_factory.factory import ARCFactory
from ryzen.apps.fleet_arc.orchestrator import FleetARC
from ryzen.packages.schemas.models import Base, ARC, ExecutionTrace
from ryzen.packages.shared.logging import setup_logging
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, Session

# Database setup
DATABASE_URL = "sqlite:///./ryzen.db"
engine = create_engine(DATABASE_URL, connect_args={"check_same_thread": False})
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

Base.metadata.create_all(bind=engine)

setup_logging()

app = FastAPI(title="Ryzen Kernel API")

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

@app.get("/governance/audit")
async def get_governance_audit(arc_id: str, db: Session = Depends(get_db)):
    from ryzen.packages.schemas.models import MemoryEntry
    audit = db.query(MemoryEntry).filter(
        MemoryEntry.arc_id == arc_id,
        MemoryEntry.memory_type == "governance"
    ).all()
    return audit

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)

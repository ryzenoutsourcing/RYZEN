import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from ryzen.packages.schemas.models import Base
from ryzen.apps.fleet_arc.orchestrator import FleetARC

engine = create_engine("sqlite:///:memory:")
SessionLocal = sessionmaker(bind=engine)

@pytest.fixture
def db():
    Base.metadata.create_all(bind=engine)
    session = SessionLocal()
    try:
        yield session
    finally:
        session.close()
        Base.metadata.drop_all(bind=engine)

def test_fleet_arc_initialization(db):
    fleet = FleetARC(db)
    arc = fleet.initialize(creator_id="primordial-creator")

    assert "Fleet ARC" in arc.name
    assert len(arc.brains) == 7

    status = arc.status
    assert status == "active"

def test_fleet_arc_topology(db):
    fleet = FleetARC(db)
    arc = fleet.initialize(creator_id="primordial-creator")

    brain_names = [b.name for b in arc.brains]
    expected_names = [
        "Executive Orchestrator", "Operations", "Sales",
        "Customer Continuity", "Analytics", "Governance", "Memory Continuity"
    ]
    for name in expected_names:
        assert name in brain_names

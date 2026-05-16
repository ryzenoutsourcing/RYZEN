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

@pytest.mark.asyncio
async def test_fleet_arc_operational_cycle_canonical(db):
    fleet = FleetARC(db)
    fleet.initialize(creator_id="primordial-1")

    text = "Schedule airport pickup tomorrow at 14:00 from Brussels Airport to Antwerp."
    result = await fleet.operational_request(text)

    assert result["status"] == "completed"
    assert result["goal"] == "schedule_booking"
    assert len(result["tasks"]) == 5
    assert any(r["status"] == "success" for r in result["results"])

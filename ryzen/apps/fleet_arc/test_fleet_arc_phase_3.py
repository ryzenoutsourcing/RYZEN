import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from ryzen.packages.schemas.models import Base, Customer
from ryzen.apps.fleet_arc.orchestrator import FleetARC

engine = create_engine("sqlite:///:memory:")
SessionLocal = sessionmaker(bind=engine)

@pytest.fixture
def db():
    Base.metadata.create_all(bind=engine)
    session = SessionLocal()
    # Create a mock customer for the test
    cust = Customer(id="cust-1", name="John Doe", email="john@example.com")
    session.add(cust)
    session.commit()
    try:
        yield session
    finally:
        session.close()
        Base.metadata.drop_all(bind=engine)

@pytest.mark.asyncio
async def test_fleet_arc_phase_3_execution_cycle(db):
    fleet = FleetARC(db)
    fleet.initialize(creator_id="primordial-1")

    text = "Schedule airport pickup tomorrow at 14:00 from Brussels Airport to Antwerp."
    result = await fleet.operational_request(text)

    assert result["status"] == "completed"
    assert result["goal"] == "schedule_booking"

    # Verify operational events (notifications, state transitions)
    from ryzen.packages.schemas.models import OperationalEvent
    events = db.query(OperationalEvent).all()
    assert any(e.event_type == "notification" for e in events)

    # Verify CRM/Adapter was called (via logs or mock if we had a more complex spy)
    # For now, we trust the successful completion of the cycle.

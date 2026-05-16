import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from ryzen.packages.schemas.models import Base, Booking, Customer, ARC, Driver, Vehicle, Schedule
from ryzen.packages.core.booking_engine import BookingExecutionEngine
from ryzen.packages.core.scheduling import SchedulingEngine
from datetime import datetime, timedelta, UTC

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

def test_booking_lifecycle_transitions(db):
    engine = BookingExecutionEngine(db)

    # Setup
    arc = ARC(id="arc-1", name="Test ARC", constitution="None", topology={}, creator_id="c1")
    cust = Customer(id="cust-1", name="John", email="john@example.com")
    booking = Booking(id="book-1", customer_id="cust-1", arc_id="arc-1", details={})
    db.add_all([arc, cust, booking])
    db.commit()

    # Transition
    engine.transition_to("arc-1", "book-1", "VALIDATED")
    assert db.query(Booking).filter(Booking.id == "book-1").first().status == "VALIDATED"

    # Check event
    from ryzen.packages.schemas.models import OperationalEvent
    event = db.query(OperationalEvent).filter(OperationalEvent.target_id == "book-1").first()
    assert event.details["new_state"] == "VALIDATED"

def test_scheduling_conflicts(db):
    engine = SchedulingEngine(db)

    # Setup
    driver = Driver(id="d1", name="Driver 1")
    vehicle = Vehicle(id="v1", make="Tesla", model="3", license_plate="XYZ")
    db.add_all([driver, vehicle])
    db.commit()

    start = datetime.now(UTC)
    end = start + timedelta(hours=2)

    # First assignment
    engine.assign_schedule("arc-1", "b1", "d1", "v1", start, end)

    # Conflict: Overlapping same driver
    with pytest.raises(ValueError, match="conflict"):
        engine.assign_schedule("arc-1", "b2", "d1", "v2", start + timedelta(hours=1), end + timedelta(hours=1))

    # Conflict: Overlapping same vehicle
    with pytest.raises(ValueError, match="conflict"):
        engine.assign_schedule("arc-1", "b3", "d2", "v1", start + timedelta(hours=1), end + timedelta(hours=1))

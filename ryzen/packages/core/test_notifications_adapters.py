import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from ryzen.packages.schemas.models import Base, OperationalEvent
from ryzen.packages.core.notifications import NotificationEngine
from ryzen.packages.core.adapters import CalendarAdapter, MessagingAdapter, CRMAdapter
import asyncio

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

def test_notification_persistence(db):
    engine = NotificationEngine(db)
    engine.send_customer_notification("arc-1", "cust-1", "confirmation", {"msg": "hello"})

    event = db.query(OperationalEvent).filter(OperationalEvent.event_type == "notification").first()
    assert event.target_id == "cust-1"
    assert event.details["type"] == "confirmation"

@pytest.mark.asyncio
async def test_adapters():
    cal = CalendarAdapter()
    msg = MessagingAdapter()
    crm = CRMAdapter()

    res1 = await cal.execute("create_event", {"date": "today"})
    res2 = await msg.execute("send_email", {"to": "john@example.com"})
    res3 = await crm.execute("update_history", {"user": "john"})

    assert res1["status"] == "success"
    assert res2["status"] == "success"
    assert res3["status"] == "success"

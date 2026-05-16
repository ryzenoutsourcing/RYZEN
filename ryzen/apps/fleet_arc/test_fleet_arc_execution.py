import pytest
import asyncio
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
async def test_fleet_arc_real_execution_cycle(db):
    fleet = FleetARC(db)
    fleet.initialize(creator_id="primordial-1")

    # Execute a "sell" task, which should route to the "Sales" brain (role: growth)
    result = await fleet.execute_task(action="sell", payload={"item": "Ryzen License", "amount": 1000})

    assert result["status"] == "success"
    assert result["result"]["metadata"]["processed_by"] == "Sales"
    assert "Processed sell" in result["result"]["output"]

    # Execute an "operate" task, which should route to "Operations" (role: execution)
    result = await fleet.execute_task(action="operate", payload={"target": "infrastructure"})
    assert result["result"]["metadata"]["processed_by"] == "Operations"

@pytest.mark.asyncio
async def test_fleet_arc_uninitialized():
    fleet = FleetARC(None)
    with pytest.raises(ValueError, match="not initialized"):
        await fleet.execute_task("test", {})

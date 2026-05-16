import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, Session
from ryzen.packages.schemas.models import Base, MemoryEntry
from ryzen.apps.memory.federation import MemoryFederationLayer

engine = create_engine("sqlite:///:memory:")
TestingSessionLocal = sessionmaker(bind=engine)

@pytest.fixture
def db():
    Base.metadata.create_all(bind=engine)
    session = TestingSessionLocal()
    try:
        yield session
    finally:
        session.close()
        Base.metadata.drop_all(bind=engine)

def test_layered_memory_storage(db: Session):
    memory_layer = MemoryFederationLayer(db)
    arc_id = "test-arc-1"

    # Store in different layers
    memory_layer.store_memory(arc_id=arc_id, content="Strategic goal", memory_type="strategic")
    memory_layer.store_memory(arc_id=arc_id, content="Operational task", memory_type="operational")
    memory_layer.store_memory(arc_id=arc_id, content="Governance audit", memory_type="governance")

    # Retrieve by layer
    strat = memory_layer.retrieve_by_layer(arc_id, "strategic")
    assert len(strat) == 1
    assert strat[0].content == "Strategic goal"

    gov = memory_layer.retrieve_by_layer(arc_id, "governance")
    assert len(gov) == 1
    assert gov[0].content == "Governance audit"

    # Invalid layer defaults to operational
    memory_layer.store_memory(arc_id=arc_id, content="Random stuff", memory_type="invalid")
    ops = memory_layer.retrieve_by_layer(arc_id, "operational")
    assert any(m.content == "Random stuff" for m in ops)

import pytest
from sqlalchemy import create_mock_engine
from sqlalchemy.orm import sessionmaker, Session
from ryzen.packages.schemas.models import Base, ARC, Brain, MemoryEntry
from ryzen.apps.memory.federation import MemoryFederationLayer
from ryzen.apps.arc_factory.factory import ARCFactory
from sqlalchemy import create_engine

# Use SQLite for testing
engine = create_engine("sqlite:///:memory:")
TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

@pytest.fixture
def db():
    Base.metadata.create_all(bind=engine)
    session = TestingSessionLocal()
    try:
        yield session
    finally:
        session.close()
        Base.metadata.drop_all(bind=engine)

def test_memory_storage(db: Session):
    memory_layer = MemoryFederationLayer(db)
    arc_id = "test-arc-1"

    entry = memory_layer.store_memory(arc_id=arc_id, content="Important operational data")

    assert entry.id is not None
    assert entry.content == "Important operational data"

    recent = memory_layer.retrieve_recent(arc_id)
    assert len(recent) == 1
    assert recent[0].content == "Important operational data"

def test_arc_factory_creation(db: Session):
    factory = ARCFactory(db)
    topology = {
        "brains": [
            {"name": "Orchestrator", "role": "executive"},
            {"name": "Operations", "role": "execution"}
        ]
    }

    arc = factory.create_arc(
        name="Fleet ARC",
        constitution="Sample constitution",
        topology_config=topology,
        creator_id="creator-123"
    )

    assert arc.id is not None
    assert arc.name == "Fleet ARC"

    # Check if brains were created
    brains = db.query(Brain).filter(Brain.arc_id == arc.id).all()
    assert len(brains) == 2
    assert any(b.name == "Orchestrator" for b in brains)

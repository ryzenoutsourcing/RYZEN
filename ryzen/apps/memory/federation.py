from typing import List, Optional, Dict, Any
from sqlalchemy.orm import Session
from ryzen.packages.schemas.models import MemoryEntry
import uuid

class MemoryFederationLayer:
    """
    Persistent memory continuity infrastructure.
    """

    def __init__(self, db_session: Session):
        self.db = db_session

    def store_memory(self, arc_id: str, content: str, memory_type: str = "operational", brain_id: Optional[str] = None, embedding: Optional[List[float]] = None) -> MemoryEntry:
        memory_id = str(uuid.uuid4())
        entry = MemoryEntry(
            id=memory_id,
            arc_id=arc_id,
            brain_id=brain_id,
            memory_type=memory_type,
            content=content,
            embedding=embedding
        )
        self.db.add(entry)
        self.db.commit()
        self.db.refresh(entry)
        return entry

    def retrieve_recent(self, arc_id: str, limit: int = 10) -> List[MemoryEntry]:
        return self.db.query(MemoryEntry).filter(MemoryEntry.arc_id == arc_id).order_by(MemoryEntry.timestamp.desc()).limit(limit).all()

    def search_semantic(self, arc_id: str, query_embedding: List[float], limit: int = 5) -> List[MemoryEntry]:
        # pgvector semantic search
        return self.db.query(MemoryEntry).filter(
            MemoryEntry.arc_id == arc_id
        ).order_by(
            MemoryEntry.embedding.l2_distance(query_embedding)
        ).limit(limit).all()

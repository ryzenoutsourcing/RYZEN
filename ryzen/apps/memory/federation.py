from typing import List, Optional, Dict, Any
from sqlalchemy.orm import Session
from ryzen.packages.schemas.models import MemoryEntry
import uuid
import logging
from datetime import datetime, UTC

logger = logging.getLogger(__name__)

class MemoryFederationLayer:
    """
    Persistent memory continuity infrastructure with layered separation.
    Supported layers: operational, strategic, creator, governance
    """

    VALID_LAYERS = ["operational", "strategic", "creator", "governance"]

    def __init__(self, db_session: Session):
        self.db = db_session

    def store_memory(self, arc_id: str, content: str, memory_type: str = "operational", brain_id: Optional[str] = None, embedding: Optional[List[float]] = None) -> MemoryEntry:
        if memory_type not in self.VALID_LAYERS:
            logger.warning(f"Invalid memory type '{memory_type}'. Defaulting to 'operational'.")
            memory_type = "operational"

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

        logger.info(f"Stored {memory_type} memory for ARC {arc_id}", extra={
            "arc_id": arc_id,
            "memory_id": memory_id,
            "memory_type": memory_type
        })
        return entry

    def retrieve_by_layer(self, arc_id: str, memory_type: str, limit: int = 10) -> List[MemoryEntry]:
        """
        Context-aware retrieval for specific memory layers.
        """
        return self.db.query(MemoryEntry).filter(
            MemoryEntry.arc_id == arc_id,
            MemoryEntry.memory_type == memory_type
        ).order_by(MemoryEntry.timestamp.desc()).limit(limit).all()

    def get_continuity_context(self, arc_id: str) -> Dict[str, Any]:
        """
        Retrieves stratified context for operational continuity.
        """
        strategic = self.retrieve_by_layer(arc_id, "strategic", limit=5)
        governance = self.retrieve_by_layer(arc_id, "governance", limit=5)
        operational = self.retrieve_recent(arc_id, limit=10)

        return {
            "strategic": [m.content for m in strategic],
            "governance": [m.content for m in governance],
            "operational": [m.content for m in operational]
        }

    def retrieve_recent(self, arc_id: str, limit: int = 10) -> List[MemoryEntry]:
        return self.db.query(MemoryEntry).filter(MemoryEntry.arc_id == arc_id).order_by(MemoryEntry.timestamp.desc()).limit(limit).all()

    def search_semantic(self, arc_id: str, query_embedding: List[float], limit: int = 5) -> List[MemoryEntry]:
        # Placeholder for actual semantic search.
        # In MVP with SQLite, we fall back to keyword search or basic filtering.
        return self.db.query(MemoryEntry).filter(
            MemoryEntry.arc_id == arc_id
        ).limit(limit).all()

    def retrieve_strategic_context(self, arc_id: str, workflow_id: Optional[str] = None) -> Dict[str, Any]:
        """
        Relevance-ranked strategic memory retrieval for operational history and failure recall.
        """
        history = self.db.query(MemoryEntry).filter(
            MemoryEntry.arc_id == arc_id,
            MemoryEntry.content.like("%failure%") | MemoryEntry.content.like("%success%")
        ).limit(10).all()

        return {
            "workflow_id": workflow_id,
            "historical_lessons": [m.content for m in history],
            "retrieved_at": datetime.now(UTC).isoformat()
        }

    def retrieve_reusable_patterns(self, arc_id: str, threshold: float = 0.8) -> List[Dict[str, Any]]:
        """
        Retrieves validated orchestration sequences from reusable patterns.
        """
        # In real production, this would query a dedicated 'stabilized_patterns' table.
        # For MVP, we filter memory for 'stabilized' content.
        patterns = self.db.query(MemoryEntry).filter(
            MemoryEntry.arc_id == arc_id,
            MemoryEntry.content.like("%stabilized_pattern%")
        ).all()

        return [{"content": p.content, "metadata": p.embedding} for p in patterns]

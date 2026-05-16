from sqlalchemy import Column, Integer, String, JSON, DateTime, ForeignKey, Text
from sqlalchemy.orm import declarative_base, relationship
from sqlalchemy.sql import func
from pgvector.sqlalchemy import Vector

Base = declarative_base()

class ARC(Base):
    __tablename__ = "arcs"

    id = Column(String, primary_key=True)
    name = Column(String, nullable=False)
    constitution = Column(Text, nullable=False)
    topology = Column(JSON, nullable=False)
    creator_id = Column(String, nullable=False)
    status = Column(String, default="active")
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

    brains = relationship("Brain", back_populates="arc")
    memory_entries = relationship("MemoryEntry", back_populates="arc")
    tasks = relationship("Task", back_populates="arc")

class Brain(Base):
    __tablename__ = "brains"

    id = Column(String, primary_key=True)
    arc_id = Column(String, ForeignKey("arcs.id"), nullable=False)
    name = Column(String, nullable=False)
    role = Column(String, nullable=False)
    specialization = Column(Text)
    governance_level = Column(Integer, default=1)
    configuration = Column(JSON)

    arc = relationship("ARC", back_populates="brains")

class MemoryEntry(Base):
    __tablename__ = "memory_entries"

    id = Column(String, primary_key=True)
    arc_id = Column(String, ForeignKey("arcs.id"), nullable=False)
    brain_id = Column(String, ForeignKey("brains.id"), nullable=True)
    memory_type = Column(String, nullable=False)  # strategic, operational, creator, etc.
    content = Column(Text, nullable=False)
    embedding = Column(Vector(1536))  # Adjust dimension as needed
    timestamp = Column(DateTime(timezone=True), server_default=func.now())

    arc = relationship("ARC", back_populates="memory_entries")

class Task(Base):
    __tablename__ = "tasks"

    id = Column(String, primary_key=True)
    arc_id = Column(String, ForeignKey("arcs.id"), nullable=False)
    assigned_brain_id = Column(String, ForeignKey("brains.id"), nullable=True)
    status = Column(String, default="pending")
    input = Column(JSON, nullable=False)
    output = Column(JSON)
    verification_state = Column(JSON)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

    arc = relationship("ARC", back_populates="tasks")

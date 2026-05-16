from sqlalchemy import Column, Integer, String, JSON, DateTime, ForeignKey, Text
from sqlalchemy.orm import declarative_base, relationship
from sqlalchemy.sql import func

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
    memory_type = Column(String, nullable=False)  # strategic, operational, creator, governance
    content = Column(Text, nullable=False)
    embedding = Column(JSON)  # SQLite compatibility
    timestamp = Column(DateTime(timezone=True), server_default=func.now())

    arc = relationship("ARC", back_populates="memory_entries")

class Task(Base):
    __tablename__ = "tasks"

    id = Column(String, primary_key=True)
    arc_id = Column(String, ForeignKey("arcs.id"), nullable=False)
    assigned_brain_id = Column(String, ForeignKey("brains.id"), nullable=True)
    status = Column(String, default="CREATED")
    input = Column(JSON, nullable=False)
    output = Column(JSON)
    verification_state = Column(JSON)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

    arc = relationship("ARC", back_populates="tasks")

# --- PHASE 2 OPERATIONAL PERSISTENCE ---

class Customer(Base):
    __tablename__ = "customers"
    id = Column(String, primary_key=True)
    name = Column(String, nullable=False)
    email = Column(String, unique=True)
    preferences = Column(JSON)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

class Booking(Base):
    __tablename__ = "bookings"
    id = Column(String, primary_key=True)
    customer_id = Column(String, ForeignKey("customers.id"), nullable=False)
    arc_id = Column(String, ForeignKey("arcs.id"), nullable=False)
    details = Column(JSON, nullable=False)
    status = Column(String, default="pending")
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

class ExecutionTrace(Base):
    __tablename__ = "execution_traces"
    id = Column(String, primary_key=True)
    trace_id = Column(String, index=True)
    arc_id = Column(String, ForeignKey("arcs.id"), nullable=False)
    step_name = Column(String, nullable=False)
    brain_id = Column(String, ForeignKey("brains.id"), nullable=True)
    input_data = Column(JSON)
    output_data = Column(JSON)
    state_transition = Column(String)
    timestamp = Column(DateTime(timezone=True), server_default=func.now())

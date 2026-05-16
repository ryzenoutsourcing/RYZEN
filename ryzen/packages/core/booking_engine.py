from typing import Dict, Any, Optional, List
from sqlalchemy.orm import Session
from ryzen.packages.schemas.models import Booking, OperationalEvent
import uuid
import logging

logger = logging.getLogger(__name__)

class BookingExecutionEngine:
    """
    Manages the booking lifecycle and persists every transition.
    """

    LIFECYCLE = [
        "REQUESTED", "VALIDATED", "PRICED", "SCHEDULED",
        "CONFIRMED", "ACTIVE", "COMPLETED", "ARCHIVED"
    ]

    def __init__(self, db_session: Session):
        self.db = db_session

    def transition_to(self, arc_id: str, booking_id: str, new_state: str, details: Optional[Dict[str, Any]] = None) -> Booking:
        if new_state not in self.LIFECYCLE:
            raise ValueError(f"Invalid state: {new_state}")

        booking = self.db.query(Booking).filter(Booking.id == booking_id).first()
        if not booking:
            raise ValueError(f"Booking {booking_id} not found")

        old_state = booking.status
        booking.status = new_state

        # Persist the transition as an event
        event = OperationalEvent(
            id=str(uuid.uuid4()),
            arc_id=arc_id,
            event_type="state_transition",
            target_id=booking_id,
            details={
                "old_state": old_state,
                "new_state": new_state,
                "additional_details": details or {}
            }
        )
        self.db.add(event)
        self.db.commit()
        self.db.refresh(booking)

        logger.info(f"Booking {booking_id} transitioned: {old_state} -> {new_state}", extra={
            "arc_id": arc_id,
            "booking_id": booking_id,
            "old_state": old_state,
            "new_state": new_state
        })

        return booking

    def get_booking(self, booking_id: str) -> Optional[Booking]:
        return self.db.query(Booking).filter(Booking.id == booking_id).first()

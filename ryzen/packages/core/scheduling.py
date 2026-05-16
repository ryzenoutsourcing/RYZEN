from typing import Dict, Any, Optional, List
from sqlalchemy.orm import Session
from ryzen.packages.schemas.models import Schedule, Driver, Vehicle, OperationalEvent
from datetime import datetime
import uuid
import logging

logger = logging.getLogger(__name__)

class SchedulingEngine:
    """
    Governed scheduling infrastructure for resource allocation and conflict detection.
    """

    def __init__(self, db_session: Session):
        self.db = db_session

    def assign_schedule(self, arc_id: str, booking_id: str, driver_id: str, vehicle_id: str, start_time: datetime, end_time: datetime) -> Schedule:
        # Conflict Detection
        if self.has_conflicts(driver_id, vehicle_id, start_time, end_time):
            logger.error(f"Scheduling conflict detected for driver {driver_id} or vehicle {vehicle_id}")
            raise ValueError("Scheduling conflict detected")

        schedule_id = str(uuid.uuid4())
        schedule = Schedule(
            id=schedule_id,
            booking_id=booking_id,
            driver_id=driver_id,
            vehicle_id=vehicle_id,
            start_time=start_time,
            end_time=end_time,
            status="scheduled"
        )
        self.db.add(schedule)

        # Log assignment event
        event = OperationalEvent(
            id=str(uuid.uuid4()),
            arc_id=arc_id,
            event_type="assignment",
            target_id=schedule_id,
            details={
                "booking_id": booking_id,
                "driver_id": driver_id,
                "vehicle_id": vehicle_id,
                "start_time": start_time.isoformat(),
                "end_time": end_time.isoformat()
            }
        )
        self.db.add(event)
        self.db.commit()
        self.db.refresh(schedule)

        logger.info(f"Schedule assigned: {schedule_id}", extra={
            "arc_id": arc_id,
            "booking_id": booking_id,
            "schedule_id": schedule_id
        })

        return schedule

    def has_conflicts(self, driver_id: str, vehicle_id: str, start_time: datetime, end_time: datetime) -> bool:
        # Check driver conflicts
        driver_conflicts = self.db.query(Schedule).filter(
            Schedule.driver_id == driver_id,
            Schedule.status != "cancelled",
            Schedule.start_time < end_time,
            Schedule.end_time > start_time
        ).count()

        if driver_conflicts > 0:
            return True

        # Check vehicle conflicts
        vehicle_conflicts = self.db.query(Schedule).filter(
            Schedule.vehicle_id == vehicle_id,
            Schedule.status != "cancelled",
            Schedule.start_time < end_time,
            Schedule.end_time > start_time
        ).count()

        return vehicle_conflicts > 0

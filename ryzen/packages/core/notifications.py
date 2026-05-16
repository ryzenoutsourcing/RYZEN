from typing import Dict, Any, Optional
from sqlalchemy.orm import Session
from ryzen.packages.schemas.models import OperationalEvent
import uuid
import logging

logger = logging.getLogger(__name__)

class NotificationEngine:
    """
    Structured operational notifications.
    """

    def __init__(self, db_session: Session):
        self.db = db_session

    def send_customer_notification(self, arc_id: str, customer_id: str, notification_type: str, data: Dict[str, Any]):
        logger.info(f"Customer Notification [{notification_type}]: {customer_id}", extra={
            "arc_id": arc_id,
            "customer_id": customer_id,
            "type": notification_type,
            "data": data
        })

        # Persist notification event
        event = OperationalEvent(
            id=str(uuid.uuid4()),
            arc_id=arc_id,
            event_type="notification",
            target_id=customer_id,
            details={
                "channel": "customer",
                "type": notification_type,
                "data": data
            }
        )
        self.db.add(event)
        self.db.commit()

    def send_internal_notification(self, arc_id: str, notification_type: str, data: Dict[str, Any]):
        logger.info(f"Internal Notification [{notification_type}]", extra={
            "arc_id": arc_id,
            "type": notification_type,
            "data": data
        })

        # Persist internal alert
        event = OperationalEvent(
            id=str(uuid.uuid4()),
            arc_id=arc_id,
            event_type="notification",
            target_id="internal",
            details={
                "channel": "internal",
                "type": notification_type,
                "data": data
            }
        )
        self.db.add(event)
        self.db.commit()

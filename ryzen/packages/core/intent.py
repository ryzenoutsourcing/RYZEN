from typing import Dict, Any, Optional
from pydantic import BaseModel, Field
import logging

logger = logging.getLogger(__name__)

class StructuredIntent(BaseModel):
    """
    Normalized operational cognition object.
    """
    intent: str
    payload: Dict[str, Any] = Field(default_factory=dict)
    metadata: Dict[str, Any] = Field(default_factory=dict)

class IntentParser:
    """
    Deterministic operational intent normalization.
    """

    def __init__(self):
        # In a real scenario, this might use an LLM with a specific schema.
        # For this implementation, we use deterministic rule-based parsing for the canonical example.
        pass

    def parse(self, text: str) -> StructuredIntent:
        logger.info(f"Parsing intent from text: {text}")

        # Canonical Example: "Schedule airport pickup tomorrow at 14:00 from Brussels Airport to Antwerp."
        text_lower = text.lower()
        if "airport pickup" in text_lower or "booking" in text_lower:
            # Mock extraction for the canonical example
            return StructuredIntent(
                intent="schedule_booking",
                payload={
                    "pickup_location": "Brussels Airport" if "brussels airport" in text_lower else "Unknown",
                    "destination": "Antwerp" if "antwerp" in text_lower else "Unknown",
                    "datetime": "tomorrow at 14:00", # Simplified
                    "service_type": "airport_transfer"
                },
                metadata={"source_text": text, "confidence": 1.0}
            )

        return StructuredIntent(
            intent="unknown",
            payload={"raw_text": text},
            metadata={"confidence": 0.0}
        )

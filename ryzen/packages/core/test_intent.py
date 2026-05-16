import pytest
from ryzen.packages.core.intent import IntentParser

def test_intent_parsing_canonical():
    parser = IntentParser()
    text = "Schedule airport pickup tomorrow at 14:00 from Brussels Airport to Antwerp."

    intent_obj = parser.parse(text)

    assert intent_obj.intent == "schedule_booking"
    assert intent_obj.payload["pickup_location"] == "Brussels Airport"
    assert intent_obj.payload["destination"] == "Antwerp"
    assert intent_obj.payload["service_type"] == "airport_transfer"

def test_intent_parsing_unknown():
    parser = IntentParser()
    text = "What is the weather today?"

    intent_obj = parser.parse(text)

    assert intent_obj.intent == "unknown"
    assert intent_obj.payload["raw_text"] == text

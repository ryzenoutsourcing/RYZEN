import logging
import sys
import json
from datetime import datetime, UTC

class StructuredFormatter(logging.Formatter):
    def format(self, record):
        log_entry = {
            "timestamp": datetime.now(UTC).isoformat(),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
            "module": record.module,
            "funcName": record.funcName,
            "lineNo": record.lineno,
        }
        if record.exc_info:
            log_entry["exception"] = self.formatException(record.exc_info)

        # Add custom trace attributes if present
        if hasattr(record, "trace_id"):
            log_entry["trace_id"] = record.trace_id
        if hasattr(record, "arc_id"):
            log_entry["arc_id"] = record.arc_id
        if hasattr(record, "brain_id"):
            log_entry["brain_id"] = record.brain_id

        return json.dumps(log_entry)

def setup_logging(level=logging.INFO):
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(StructuredFormatter())

    root_logger = logging.getLogger()
    root_logger.setLevel(level)

    # Remove existing handlers to avoid duplicates
    for h in root_logger.handlers[:]:
        root_logger.removeHandler(h)

    root_logger.addHandler(handler)

    # Silent noisy loggers
    logging.getLogger("uvicorn.access").setLevel(logging.WARNING)

    return root_logger

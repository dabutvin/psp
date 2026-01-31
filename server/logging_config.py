"""
Structured logging configuration for PSP server.

Provides JSON-formatted logs for production use with contextual fields
for better observability and log aggregation.
"""

import json
import logging
import sys
from datetime import datetime, timezone
from typing import Any


class JSONFormatter(logging.Formatter):
    """
    JSON log formatter for structured logging.
    
    Output format:
    {
        "timestamp": "2024-01-15T10:30:00.123456Z",
        "level": "INFO",
        "logger": "fetch",
        "message": "Fetched 100 messages",
        "context": { ... extra fields ... }
    }
    """

    def format(self, record: logging.LogRecord) -> str:
        log_entry = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
        }

        # Add exception info if present
        if record.exc_info:
            log_entry["exception"] = self.formatException(record.exc_info)

        # Add extra context fields (anything passed via extra={})
        context = {}
        for key, value in record.__dict__.items():
            if key not in (
                "name", "msg", "args", "created", "filename", "funcName",
                "levelname", "levelno", "lineno", "module", "msecs",
                "pathname", "process", "processName", "relativeCreated",
                "stack_info", "exc_info", "exc_text", "thread", "threadName",
                "taskName", "message",
            ):
                context[key] = value

        if context:
            log_entry["context"] = context

        return json.dumps(log_entry, default=str)


class PrettyFormatter(logging.Formatter):
    """
    Human-readable formatter for development/CLI use.
    
    Output format:
    2024-01-15 10:30:00 INFO  [fetch] Fetched 100 messages
    """

    COLORS = {
        "DEBUG": "\033[36m",     # Cyan
        "INFO": "\033[32m",      # Green
        "WARNING": "\033[33m",   # Yellow
        "ERROR": "\033[31m",     # Red
        "CRITICAL": "\033[35m",  # Magenta
    }
    RESET = "\033[0m"

    def __init__(self, use_colors: bool = True):
        super().__init__()
        self.use_colors = use_colors and sys.stderr.isatty()

    def format(self, record: logging.LogRecord) -> str:
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        level = record.levelname.ljust(5)
        
        if self.use_colors:
            color = self.COLORS.get(record.levelname, "")
            level = f"{color}{level}{self.RESET}"

        message = record.getMessage()
        
        # Format: timestamp LEVEL [logger] message
        formatted = f"{timestamp} {level} [{record.name}] {message}"

        # Add context fields if present
        context_parts = []
        for key, value in record.__dict__.items():
            if key not in (
                "name", "msg", "args", "created", "filename", "funcName",
                "levelname", "levelno", "lineno", "module", "msecs",
                "pathname", "process", "processName", "relativeCreated",
                "stack_info", "exc_info", "exc_text", "thread", "threadName",
                "taskName", "message",
            ):
                context_parts.append(f"{key}={value}")

        if context_parts:
            formatted += f" | {', '.join(context_parts)}"

        # Add exception if present
        if record.exc_info:
            formatted += f"\n{self.formatException(record.exc_info)}"

        return formatted


def setup_logging(
    level: int = logging.INFO,
    json_format: bool = False,
    logger_name: str | None = None,
) -> logging.Logger:
    """
    Configure logging for the application.
    
    Args:
        level: Log level (default: INFO)
        json_format: Use JSON format (for production), else pretty format
        logger_name: Specific logger to configure (None = root logger)
    
    Returns:
        Configured logger instance
    """
    logger = logging.getLogger(logger_name)
    logger.setLevel(level)

    # Remove existing handlers to avoid duplicates
    logger.handlers.clear()

    # Create handler
    handler = logging.StreamHandler(sys.stderr)
    handler.setLevel(level)

    # Set formatter
    if json_format:
        handler.setFormatter(JSONFormatter())
    else:
        handler.setFormatter(PrettyFormatter())

    logger.addHandler(handler)

    # Prevent propagation to avoid duplicate logs
    if logger_name:
        logger.propagate = False

    return logger


def get_logger(name: str) -> logging.Logger:
    """
    Get a logger with the specified name.
    
    Use this in modules:
        logger = get_logger(__name__)
        logger.info("Something happened", extra={"count": 42})
    """
    return logging.getLogger(name)


class LogContext:
    """
    Context manager for adding fields to all log messages within a block.
    
    Usage:
        with LogContext(request_id="abc123", user="john"):
            logger.info("Processing request")  # includes request_id, user
    
    Note: This uses a LoggerAdapter approach for simplicity.
    """

    def __init__(self, logger: logging.Logger, **context: Any):
        self.logger = logger
        self.context = context
        self._adapter: logging.LoggerAdapter | None = None

    def __enter__(self) -> logging.LoggerAdapter:
        self._adapter = logging.LoggerAdapter(self.logger, self.context)
        return self._adapter

    def __exit__(self, *args):
        pass


# Convenience function for stats logging
def log_stats(logger: logging.Logger, operation: str, **stats: Any) -> None:
    """
    Log operation statistics in a consistent format.
    
    Usage:
        log_stats(logger, "fetch", messages_fetched=100, duration_ms=1234)
    """
    logger.info(
        f"{operation} completed",
        extra={"operation": operation, "stats": stats},
    )

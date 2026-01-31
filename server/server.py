"""
FastAPI server for PSP Classifieds.

Read-only API for the iPhone app to access messages, hashtags, and stats.
"""

from contextlib import asynccontextmanager
from typing import AsyncGenerator

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware
from fastapi.responses import JSONResponse
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from slowapi.util import get_remote_address

from config import get_settings
from db import get_database
from logging_config import get_logger, setup_logging

# Set up logging
setup_logging()
logger = get_logger(__name__)

# Rate limiter
limiter = Limiter(key_func=get_remote_address)


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncGenerator[None, None]:
    """
    Application lifespan handler.
    
    Manages database connection pool lifecycle.
    """
    # Startup
    logger.info("Starting PSP API server")
    db = get_database()
    await db.connect()
    logger.info("Database connection pool established")
    
    yield
    
    # Shutdown
    logger.info("Shutting down PSP API server")
    await db.disconnect()
    logger.info("Database connection pool closed")


# Create FastAPI app
app = FastAPI(
    title="PSP Classifieds API",
    description="Read-only API for Park Slope Parents Classifieds messages",
    version="1.0.0",
    lifespan=lifespan,
    docs_url="/docs",
    redoc_url="/redoc",
    openapi_url="/openapi.json",
)

# Add rate limiter
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

# Add CORS middleware (configure origins as needed)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Configure for production
    allow_credentials=True,
    allow_methods=["GET"],  # Read-only API
    allow_headers=["*"],
)

# Add gzip compression for responses > 1KB
app.add_middleware(GZipMiddleware, minimum_size=1000)


# Import and include routers
from routers import hashtags, messages, stats

app.include_router(messages.router, prefix="/api/v1", tags=["messages"])
app.include_router(hashtags.router, prefix="/api/v1", tags=["hashtags"])
app.include_router(stats.router, prefix="/api/v1", tags=["stats"])


@app.get("/", include_in_schema=False)
async def root():
    """Root endpoint - redirect to docs."""
    return {"message": "PSP Classifieds API", "docs": "/docs"}


@app.get("/health")
async def health_check():
    """Health check endpoint for monitoring."""
    db = get_database()
    try:
        await db.fetchval("SELECT 1")
        return {"status": "healthy", "database": "connected"}
    except Exception as e:
        logger.error(f"Health check failed: {e}")
        return JSONResponse(
            status_code=503,
            content={"status": "unhealthy", "database": "disconnected", "error": str(e)},
        )


def run_server(host: str = "0.0.0.0", port: int = 8000, reload: bool = False):
    """
    Run the API server.
    
    Args:
        host: Host to bind to
        port: Port to bind to
        reload: Enable auto-reload for development
    """
    import uvicorn
    
    settings = get_settings()
    
    uvicorn.run(
        "server:app",
        host=host,
        port=port,
        reload=reload,
        log_level="info",
    )


if __name__ == "__main__":
    run_server()

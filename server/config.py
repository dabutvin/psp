"""
Configuration module for PSP server.
Loads environment variables and provides typed settings.
"""

import os
from functools import lru_cache

from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    """Application settings loaded from environment variables."""

    # Groups.io API
    groups_io_api_token: str
    groups_io_group_id: int = 8407
    groups_io_base_url: str = "https://groups.io/api/v1"

    # Database
    database_url: str

    # Backfill
    backfill_delay_seconds: int = 5

    # API Server
    api_host: str = "0.0.0.0"
    api_port: int = 8000

    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"


@lru_cache
def get_settings() -> Settings:
    """
    Get cached settings instance.
    Uses lru_cache to avoid re-reading .env on every call.
    """
    return Settings()


# Convenience access for common settings
def get_db_url() -> str:
    """Get database URL."""
    return get_settings().database_url


def get_api_token() -> str:
    """Get Groups.io API token."""
    return get_settings().groups_io_api_token


def get_group_id() -> int:
    """Get Groups.io group ID."""
    return get_settings().groups_io_group_id

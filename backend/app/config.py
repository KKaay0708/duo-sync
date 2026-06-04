"""App configuration loaded from environment variables."""

from functools import lru_cache

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    database_url: str = Field(..., description="Postgres connection string")
    token_encryption_key: str = Field(..., description="Fernet key for encrypting refresh tokens")
    jwt_secret: str = Field(..., description="Secret for signing session JWTs")
    spotify_client_id: str = Field(..., description="Spotify Web API client ID")
    jwt_lifetime_days: int = 30
    app_env: str = "dev"

    # Worker
    worker_enabled: bool = True
    worker_poll_interval: int = 8

    # APNs (optional — empty key_id disables push)
    apns_key_id: str = ""
    apns_team_id: str = ""
    apns_topic: str = "kkaay.duo-sync"
    apns_key_path: str = ""
    apns_private_key: str = ""
    apns_use_sandbox: bool = True

    # Web Push (PWA / browser notifications)
    vapid_public_key: str = ""
    vapid_private_key: str = ""
    vapid_subject: str = ""

    @property
    def is_dev(self) -> bool:
        return self.app_env.lower() == "dev"

    @property
    def apns_configured(self) -> bool:
        return bool(self.apns_key_id) and bool(self.apns_team_id) and (
            bool(self.apns_key_path) or bool(self.apns_private_key)
        )

    @property
    def web_push_configured(self) -> bool:
        return bool(self.vapid_public_key) and bool(self.vapid_private_key) and bool(self.vapid_subject)


@lru_cache
def get_settings() -> Settings:
    return Settings()

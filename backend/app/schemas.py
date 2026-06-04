"""Pydantic request/response models."""

from __future__ import annotations

import datetime as dt
from uuid import UUID

from pydantic import BaseModel, Field


class SpotifyAuthRequest(BaseModel):
    """Payload sent by the iOS app after it completes Spotify PKCE OAuth."""

    access_token: str
    refresh_token: str
    expires_in: int = Field(..., ge=1, description="Access-token lifetime in seconds")
    scope: str | None = None


class UserOut(BaseModel):
    id: UUID
    spotify_id: str
    display_name: str | None
    email: str | None
    avatar_url: str | None
    created_at: dt.datetime


class SessionOut(BaseModel):
    """What we return after /auth/spotify — the JWT plus the user."""

    session_token: str
    user: UserOut


class DeviceTokenRequest(BaseModel):
    apns_token: str = Field(..., min_length=32, description="Hex APNs device token")


class WebPushSubscriptionRequest(BaseModel):
    endpoint: str = Field(..., description="Browser push service endpoint URL")
    p256dh: str = Field(..., description="Public key (base64url)")
    auth: str = Field(..., description="Auth secret (base64url)")
    user_agent: str | None = None


class VapidPublicKeyResponse(BaseModel):
    public_key: str

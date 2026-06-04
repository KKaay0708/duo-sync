"""Token encryption (Fernet) and session JWT issuance/verification."""

from __future__ import annotations

import datetime as dt
from uuid import UUID

from cryptography.fernet import Fernet, InvalidToken
from fastapi import Depends, Header, HTTPException, status
from jose import JWTError, jwt

from .config import Settings, get_settings


# ---------- Refresh-token encryption -----------------------------------------


def _fernet(settings: Settings) -> Fernet:
    return Fernet(settings.token_encryption_key.encode())


def encrypt_token(plaintext: str, settings: Settings | None = None) -> str:
    settings = settings or get_settings()
    return _fernet(settings).encrypt(plaintext.encode()).decode()


def decrypt_token(ciphertext: str, settings: Settings | None = None) -> str:
    settings = settings or get_settings()
    try:
        return _fernet(settings).decrypt(ciphertext.encode()).decode()
    except InvalidToken as exc:  # pragma: no cover
        raise HTTPException(500, "Token decryption failed") from exc


# ---------- Session JWTs -----------------------------------------------------


def issue_session_jwt(user_id: UUID, settings: Settings | None = None) -> str:
    settings = settings or get_settings()
    now = dt.datetime.now(dt.timezone.utc)
    payload = {
        "sub": str(user_id),
        "iat": int(now.timestamp()),
        "exp": int((now + dt.timedelta(days=settings.jwt_lifetime_days)).timestamp()),
    }
    return jwt.encode(payload, settings.jwt_secret, algorithm="HS256")


def decode_session_jwt(token: str, settings: Settings | None = None) -> UUID:
    settings = settings or get_settings()
    try:
        payload = jwt.decode(token, settings.jwt_secret, algorithms=["HS256"])
    except JWTError as exc:
        raise HTTPException(401, "Invalid or expired session") from exc
    sub = payload.get("sub")
    if not sub:
        raise HTTPException(401, "Session missing subject")
    return UUID(sub)


# ---------- FastAPI dependency: extract authed user -------------------------


def require_user(
    authorization: str | None = Header(default=None),
    settings: Settings = Depends(get_settings),
) -> UUID:
    """Dependency that returns the authenticated user's UUID.

    Expects `Authorization: Bearer <jwt>`.
    """
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing Bearer token",
            headers={"WWW-Authenticate": "Bearer"},
        )
    token = authorization.split(" ", 1)[1]
    return decode_session_jwt(token, settings)

"""Endpoints scoped to the authenticated user."""

from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status

from .. import db
from ..config import get_settings
from ..schemas import (
    DeviceTokenRequest,
    UserOut,
    VapidPublicKeyResponse,
    WebPushSubscriptionRequest,
)
from ..security import require_user

router = APIRouter(prefix="/me", tags=["me"])


@router.get("", response_model=UserOut)
async def get_me(user_id: UUID = Depends(require_user)) -> UserOut:
    async with db.pool().acquire() as conn:
        row = await conn.fetchrow(
            """
            select id, spotify_id, display_name, email, avatar_url, created_at
            from users where id = $1
            """,
            user_id,
        )
    if row is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "User not found")
    return UserOut(**dict(row))


@router.post("/device-token", status_code=status.HTTP_204_NO_CONTENT)
async def register_device_token(
    body: DeviceTokenRequest,
    user_id: UUID = Depends(require_user),
) -> None:
    """Register an APNs device token so the poll worker can push to this device.

    Idempotent on (user_id, apns_token).
    """
    async with db.pool().acquire() as conn:
        await conn.execute(
            """
            insert into sessions (user_id, apns_token)
            values ($1, $2)
            on conflict (user_id, apns_token) do update
              set last_seen_at = now()
            """,
            user_id, body.apns_token,
        )


@router.delete("", status_code=status.HTTP_204_NO_CONTENT)
async def delete_account(user_id: UUID = Depends(require_user)) -> None:
    """Hard-delete the user (cascade removes tokens, sessions, friendships)."""
    async with db.pool().acquire() as conn:
        await conn.execute("delete from users where id = $1", user_id)


# ---------------------------------------------------------------------------
# Web Push (PWA notifications)
# ---------------------------------------------------------------------------


@router.post("/web-push-subscription", status_code=status.HTTP_204_NO_CONTENT)
async def register_web_push(
    body: WebPushSubscriptionRequest,
    user_id: UUID = Depends(require_user),
) -> None:
    """Browser calls this after `pushManager.subscribe()` succeeds.

    Idempotent on `endpoint` — the unique constraint on web_push_subscriptions
    means re-subscribing from the same browser updates last_seen_at rather
    than inserting duplicates.
    """
    async with db.pool().acquire() as conn:
        await conn.execute(
            """
            insert into web_push_subscriptions (user_id, endpoint, p256dh, auth, user_agent)
            values ($1, $2, $3, $4, $5)
            on conflict (endpoint) do update
              set user_id      = excluded.user_id,
                  p256dh       = excluded.p256dh,
                  auth         = excluded.auth,
                  user_agent   = excluded.user_agent,
                  last_seen_at = now()
            """,
            user_id, body.endpoint, body.p256dh, body.auth, body.user_agent,
        )


@router.delete("/web-push-subscription", status_code=status.HTTP_204_NO_CONTENT)
async def unregister_web_push(
    endpoint: str,
    user_id: UUID = Depends(require_user),
) -> None:
    async with db.pool().acquire() as conn:
        await conn.execute(
            "delete from web_push_subscriptions where user_id=$1 and endpoint=$2",
            user_id, endpoint,
        )

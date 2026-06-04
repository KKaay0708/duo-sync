"""Web Push (VAPID) dispatch.

PWA notifications use the W3C Push API + VAPID. Unlike APNs this does
not involve Apple at all — the browser holds a subscription that points
to a push service (Mozilla, Google, Apple — whoever runs the browser).
We post our signed payload to that endpoint and the browser handles
the rest.

iOS 16.4+ supports Web Push for installed PWAs ("Add to Home Screen").
"""

from __future__ import annotations

import asyncio
import json
import logging
from dataclasses import dataclass

from pywebpush import WebPushException, webpush

from .config import Settings, get_settings

log = logging.getLogger(__name__)


@dataclass
class WebPushSubscription:
    endpoint: str
    p256dh: str
    auth: str


def _vapid_claims(settings: Settings) -> dict:
    return {"sub": settings.vapid_subject}


def _send_sync(subscription: WebPushSubscription, payload: dict, settings: Settings) -> bool:
    try:
        webpush(
            subscription_info={
                "endpoint": subscription.endpoint,
                "keys": {"p256dh": subscription.p256dh, "auth": subscription.auth},
            },
            data=json.dumps(payload),
            vapid_private_key=settings.vapid_private_key,
            vapid_claims=_vapid_claims(settings),
        )
        return True
    except WebPushException as exc:
        # 404 / 410 → subscription gone (browser revoked or stale).
        # Caller can use this signal to delete the row.
        status = getattr(getattr(exc, "response", None), "status_code", None)
        log.warning("WebPush failed status=%s endpoint=%s err=%s",
                    status, subscription.endpoint[:50], exc)
        return False
    except Exception as exc:  # noqa: BLE001
        log.warning("WebPush unexpected error: %s", exc)
        return False


async def send_push(subscription: WebPushSubscription, payload: dict) -> bool:
    """Async wrapper — pywebpush is blocking, so we run it in a thread."""
    settings = get_settings()
    if not settings.web_push_configured:
        return False
    return await asyncio.to_thread(_send_sync, subscription, payload, settings)


async def send_push_to_many(
    subscriptions: list[WebPushSubscription],
    payload: dict,
) -> int:
    """Returns number of successful deliveries."""
    results = await asyncio.gather(
        *(send_push(s, payload) for s in subscriptions),
        return_exceptions=True,
    )
    return sum(1 for r in results if r is True)

"""APNs silent-push client.

Soft-fails when credentials aren't configured (dev on a free Apple Developer
account). Once configured, dispatches ``content-available: 1`` payloads that
wake the iOS app in the background so it can pull fresh now-playing state
and call ``WidgetCenter.reloadAllTimelines()``.
"""

from __future__ import annotations

import logging
from typing import Iterable

from aioapns import APNs, NotificationRequest, PushType
from aioapns.common import PRIORITY_NORMAL

from .config import Settings, get_settings

log = logging.getLogger(__name__)

_client: APNs | None = None


def _build_client(settings: Settings) -> APNs | None:
    if not settings.apns_configured:
        return None

    # aioapns accepts either a file path or in-memory key contents.
    key_kwargs: dict = {}
    if settings.apns_private_key:
        key_kwargs["key"] = settings.apns_private_key
    else:
        key_kwargs["key"] = settings.apns_key_path  # path string

    return APNs(
        key_id=settings.apns_key_id,
        team_id=settings.apns_team_id,
        topic=settings.apns_topic,
        use_sandbox=settings.apns_use_sandbox,
        **key_kwargs,
    )


async def get_client() -> APNs | None:
    global _client
    if _client is not None:
        return _client
    _client = _build_client(get_settings())
    if _client is None:
        log.info("APNs not configured — silent push disabled")
    return _client


async def send_silent_push(
    device_tokens: Iterable[str],
    payload: dict | None = None,
) -> int:
    """Sends a silent push to every device token. Returns count of successes.

    iOS treats ``content-available: 1`` + no alert/sound as a background
    wake-up. We include a small payload version so the app can debounce
    duplicate wakes.
    """
    client = await get_client()
    if client is None:
        return 0

    body = {
        "aps": {
            "content-available": 1,
        }
    }
    if payload:
        body.update(payload)

    sent = 0
    for token in device_tokens:
        try:
            req = NotificationRequest(
                device_token=token,
                message=body,
                push_type=PushType.BACKGROUND,
                priority=PRIORITY_NORMAL,
            )
            result = await client.send_notification(req)
            if result.is_successful:
                sent += 1
            else:
                log.warning("APNs rejected token=%s status=%s desc=%s",
                            token[:8], result.status, result.description)
        except Exception as exc:  # noqa: BLE001
            log.warning("APNs send failed for token=%s: %s", token[:8], exc)
    return sent

"""Public endpoints for Web Push key discovery."""

from fastapi import APIRouter, Depends, HTTPException

from ..config import Settings, get_settings
from ..schemas import VapidPublicKeyResponse

router = APIRouter(prefix="/web-push", tags=["web-push"])


@router.get("/vapid-public-key", response_model=VapidPublicKeyResponse)
async def vapid_public_key(settings: Settings = Depends(get_settings)) -> VapidPublicKeyResponse:
    if not settings.vapid_public_key:
        raise HTTPException(503, "VAPID public key not configured")
    return VapidPublicKeyResponse(public_key=settings.vapid_public_key)

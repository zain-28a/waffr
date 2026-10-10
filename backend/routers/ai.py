from fastapi import APIRouter, Depends, HTTPException

import ai_service
from ai_schemas import (
    CategorizeRequest,
    CategorizeResponse,
    InsightsRequest,
    InsightsResponse,
)
from auth import get_current_user
from models import User

router = APIRouter(prefix="/ai", tags=["ai"])


def _run(user: User, kind: str, call):
    try:
        ai_service.check_quota(user.id, kind)
        return call()
    except ai_service.AiRateLimited:
        raise HTTPException(
            status_code=429,
            detail="Daily AI limit reached",
        ) from None
    except ai_service.AiUnavailable:
        raise HTTPException(
            status_code=503,
            detail="AI is temporarily unavailable",
        ) from None


@router.post("/insights", response_model=InsightsResponse)
def insights(
    data: InsightsRequest,
    current_user: User = Depends(get_current_user),
):
    return _run(current_user, "insights", lambda: ai_service.insights(data))


@router.post("/categorize", response_model=CategorizeResponse)
def categorize(
    data: CategorizeRequest,
    current_user: User = Depends(get_current_user),
):
    return _run(
        current_user,
        "categorize",
        lambda: ai_service.categorize(data),
    )

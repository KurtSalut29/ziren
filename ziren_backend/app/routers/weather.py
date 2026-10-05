"""
/weather — the forecast Ziren reads to the resident on Home.

Any signed-in account. The position is optional (no GPS fix yet -> Naval) and
is snapped to a ~5 km grid before anything leaves Ziren; see weather_service.
"""

from fastapi import APIRouter, Depends, HTTPException, Query, Request, status

from app.core.dependencies import get_current_user
from app.core.rate_limit import limiter
from app.services import weather_service

router = APIRouter()


@router.get("/")
@limiter.limit("30/minute")
def get_weather(
    request: Request,
    lat: float | None = Query(None, ge=-90, le=90),
    lng: float | None = Query(None, ge=-180, le=180),
    current_user: dict = Depends(get_current_user),
):
    try:
        return weather_service.forecast(lat, lng)
    except weather_service.OutsideCoverage as e:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail=str(e))
    except weather_service.WeatherUnavailable as e:
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail=str(e))

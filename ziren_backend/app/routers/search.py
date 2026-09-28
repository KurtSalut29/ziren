"""/search — Global Search (spec Section 18)."""

from fastapi import APIRouter, Depends, Query

from app.core.dependencies import require_role
from app.services import search_service

router = APIRouter()

_searcher = Depends(require_role("agency_admin", "provincial_admin"))


@router.get("/")
def global_search(
    q: str = Query(..., min_length=2),
    current_user: dict = _searcher,
):
    return search_service.search(q, current_user)

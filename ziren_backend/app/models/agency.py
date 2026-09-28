"""
Agency & Station Pydantic models.
Keep in sync with public.agencies and public.stations tables.
"""

from uuid import UUID
from datetime import datetime
from pydantic import BaseModel


class AgencyType:
    BFP = "BFP"
    PNP = "PNP"
    MDRRMO = "MDRRMO"


class AgencyResponse(BaseModel):
    id: UUID
    name: str
    agency_type: str
    municipality: str
    province: str
    region: str
    contact_number: str | None
    is_active: bool
    created_at: datetime


class StationResponse(BaseModel):
    id: UUID
    agency_id: UUID
    name: str
    address: str | None
    is_active: bool
    created_at: datetime

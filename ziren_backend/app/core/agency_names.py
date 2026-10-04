"""What a Provincial Admin's office is called.

Evaluator finding #35 (2026-10-05): provincial accounts were labelled with the
municipal office's name, "MDRRMO", though they represent the province. The
provincial disaster office is the PDRRMO; BFP and PNP keep their agency names
with "Provincial Office".
"""

_PROVINCIAL = {
    "BFP": "BFP Provincial Office",
    "PNP": "PNP Provincial Office",
    "MDRRMO": "PDRRMO",
}


def provincial_office_name(agency_type: str | None) -> str:
    """'PDRRMO', 'BFP Provincial Office', ... or 'the provincial office'."""
    key = (agency_type or "").upper()
    return _PROVINCIAL.get(key, "the provincial office")

"""
The "Ziren code": how a responder knows the person in front of them is the one
who reported.

Asked by a teacher reviewing the system: when the crew arrives, how do they
identify the reporter - and what if the reporter's appearance does not match
what the crew expects (a transgender person, for example)? Appearance and
gender are the wrong thing to identify anyone by. This is a fact only the
reporter's phone shows them: four digits per report. The crew asks for it; the
reporter reads it off their report. Nobody is judged by how they look, and
nobody needs a sex or gender field to be found.

Derived, not stored: an HMAC of the incident id with the server's secret key,
so it needs no column and cannot be worked out from the incident id alone. The
reporter sees it on their own report; the assigned responder on the
assignment; the dispatcher in the incident dialog, to confirm a caller.
"""

import hashlib
import hmac

from app.core.config import settings


def meet_code(incident_id: object) -> str:
    key = (settings.secret_key or "ziren-meet-code").encode()
    digest = hmac.new(key, f"meet:{incident_id}".encode(), hashlib.sha256).digest()
    return f"{int.from_bytes(digest[:4], 'big') % 10000:04d}"

# features/

Each top-level folder is one self-contained feature slice.
Features import from `core/` and `shared/` but never from each other directly.

## Feature folders (to be created per phase)
- `auth/`              — Phase 1: Login, Register, session management
- `incident_report/`   — Phase 3: Incident submission, status tracking
- `resq_chat/`         — Phase 8: ResQ AI Chat (Claude, assistive only)
- `notifications/`     — Phase 10: Push notifications

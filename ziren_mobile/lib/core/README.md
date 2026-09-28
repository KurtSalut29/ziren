# core/

App-wide infrastructure: network clients, routing, constants, environment config,
error handling, and anything that cuts across all features.

## Planned sub-folders
- `config/`   — environment variables, app constants
- `network/`  — HTTP client setup (Supabase, FastAPI)
- `routing/`  — app router / navigation
- `errors/`   — base error types, failure classes
- `utils/`    — pure utility functions (formatters, validators)

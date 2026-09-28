"""
Application settings, loaded from environment variables (.env in development).

Import the shared `settings` instance from here — never construct Settings()
again elsewhere, or each caller ends up with its own copy of the parsed
environment.

Field names map to env vars case-insensitively: `supabase_url` reads
SUPABASE_URL. See .env.example for the full documented set.
"""

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        # The .env is shared with tooling that defines vars this app does not
        # read; unknown keys must not crash startup.
        extra="ignore",
    )

    # ---- App ----
    environment: str = "development"
    secret_key: str = ""

    # ---- Supabase ----
    # SERVICE ROLE key — server-side only, never sent to a client.
    supabase_url: str = ""
    supabase_service_key: str = ""

    # ---- Speech-to-text for voice reports ----
    # Which recogniser transcribes a resident's recording, or "" for none.
    #
    # Empty is a supported state, not a broken one: reports still land, still
    # carry their audio, and are still ranked on whatever text exists. Naming
    # an engine that cannot be built degrades the same way — see
    # asr_engines.load().
    #
    # Known values: faster-whisper-small, faster-whisper-medium,
    #               faster-whisper-small-fil (language pinned to Tagalog).
    asr_engine: str = ""

    # ---- Claude API (ResQ Chat) ----
    claude_api_key: str = ""  # Optional until Phase 8

    # ---- CORS ----
    # Comma-separated list of allowed origins
    cors_origins_raw: str = "http://localhost:3000"

    @property
    def cors_origins(self) -> list[str]:
        return [o.strip() for o in self.cors_origins_raw.split(",")]

    # ---- Dashboard base URL ----
    # Where emailed links (invite, password reset) send the recipient.
    #
    # This was previously hardcoded to http://localhost:3001/accept-invite in
    # the invite call, which was wrong twice over: the dashboard serves on
    # 3000, and "localhost" resolves to whatever device OPENS the mail. An
    # invite read on a phone pointed the phone at itself and died with
    # ERR_CONNECTION_REFUSED.
    #
    # Set this to a host the RECIPIENT can reach. For phone testing on the
    # same wi-fi that means the dev machine's LAN address, e.g.
    #     DASHBOARD_BASE_URL=http://192.168.100.9:3000
    # and the same origin must be present in CORS_ORIGINS_RAW *and* in
    # Supabase > Authentication > URL Configuration > Redirect URLs. Supabase
    # silently falls back to the project Site URL for any redirect not on that
    # allow-list, and the fallback drops the /accept-invite path with it, so a
    # half-configured value is worse than none.
    dashboard_base_url: str = "http://localhost:3000"

    @property
    def accept_invite_url(self) -> str:
        return f"{self.dashboard_base_url.rstrip('/')}/accept-invite"

    @property
    def reset_password_url(self) -> str:
        # The page a password-reset email lands on. Like accept_invite_url it
        # must be on Supabase's Redirect URLs allow-list; when it is not,
        # Supabase falls back to the Site URL with the recovery tokens in the
        # fragment, and the dashboard's root page forwards them here.
        return f"{self.dashboard_base_url.rstrip('/')}/reset-password"

    # ---- Dev admin bypass (development only) ----
    dev_admin_email: str = ""
    dev_admin_password: str = ""

    # ---- Rate limiting ----
    rate_limit_login: str = "10/minute"
    rate_limit_incident_submit: str = "20/minute"
    # SOS is stricter: max 3 per hour at the IP level
    # (account-level cooldown is enforced in the service layer)
    rate_limit_sos_submit: str = "3/hour"


# Single shared instance — import this everywhere
settings = Settings()  # type: ignore[call-arg]

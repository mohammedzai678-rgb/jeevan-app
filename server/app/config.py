from __future__ import annotations

from functools import lru_cache

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore", case_sensitive=False)

    allowed_origins: str = "*"

    supabase_url: str = ""
    supabase_service_role_key: str = ""
    supabase_jwt_secret: str = ""

    device_api_key: str = ""
    sensor_sequence: str = "read_max30102:15,read_dht11:4,read_ad8232:6"
    default_owner_user_id: str = ""
    legacy_unauth_reminder_ack: bool = True
    metric_ttl_s: float = 60.0
    device_online_s: float = 15.0

    persist_interval_s: float = 30.0
    mirror_live_stream: bool = False
    mirror_interval_s: float = 5.0

    gemini_api_key: str = ""
    gemini_model: str = "gemini-3.6-flash"
    openai_api_key: str = ""
    openai_mediscan_model: str = "gpt-4.1-mini"
    huggingface_api_key: str = ""
    huggingface_model: str = "meta-llama/Llama-3.1-8B-Instruct"
    ai_text_provider: str = "gemini"
    llm_timeout_s: float = 30.0

    brevo_api_key: str = ""
    brevo_from_email: str = ""
    brevo_from_name: str = "Jeevan"
    brevo_sms_sender: str = "Jeevan"
    brevo_whatsapp_sender_number: str = ""
    brevo_whatsapp_sos_template_id: str = ""
    brevo_whatsapp_safe_template_id: str = ""
    brevo_whatsapp_video_invite_template_id: str = ""
    brevo_whatsapp_medication_template_id: str = ""
    app_public_url: str = Field(default="https://jeevan-app-backend-production.up.railway.app")

    # SMTP fallback (when Brevo is not configured)
    smtp_host: str = ""
    smtp_port: int = 587
    smtp_user: str = ""
    smtp_password: str = ""
    smtp_from_email: str = ""

    tomtom_api_key: str = ""
    openweather_key: str = ""
    agora_app_id: str = ""
    agora_app_certificate: str = ""

    @property
    def cors_origins(self) -> list[str]:
        return [o.strip() for o in self.allowed_origins.split(",") if o.strip()]

    @property
    def persistence_enabled(self) -> bool:
        return bool(self.supabase_url and self.supabase_service_role_key)

    def parsed_sequence(self) -> list[tuple[str, float]]:
        seq: list[tuple[str, float]] = []
        for part in self.sensor_sequence.split(","):
            part = part.strip()
            if not part:
                continue
            cmd, _, secs = part.partition(":")
            try:
                seq.append((cmd.strip(), float(secs) if secs else 5.0))
            except ValueError:
                continue
        return seq or [("read_max30102", 15.0)]


@lru_cache
def get_settings() -> Settings:
    return Settings()

from __future__ import annotations

import time

import jwt
import pytest
from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app
from app.rag.index import HybridIndex

SECRET = "test-secret-test-secret-test-secret-1234"
DEVICE_KEY = "dev-key-123"
USER_A = "11111111-1111-1111-1111-111111111111"
USER_B = "22222222-2222-2222-2222-222222222222"


def token(uid: str = USER_A, **extra) -> str:
    payload = {"sub": uid, "aud": "authenticated", "role": "authenticated", "iss": "https://test.supabase.co/auth/v1", "exp": int(time.time()) + 600, "email": f"{uid[:4]}@x.com", **extra}
    return jwt.encode(payload, SECRET, algorithm="HS256")


def auth(uid: str = USER_A) -> dict[str, str]:
    return {"Authorization": f"Bearer {token(uid)}"}


@pytest.fixture()
def settings() -> Settings:
    return Settings(
        _env_file=None,
        supabase_url="https://test.supabase.co",
        supabase_jwt_secret=SECRET,
        device_api_key=DEVICE_KEY,
        sensor_sequence="read_max30102:15,read_dht11:4,read_ad8232:6",
    )


@pytest.fixture()
def client(settings):
    index = HybridIndex()  # BM25 only: no model downloads in tests
    index.build_shared()
    with TestClient(create_app(settings, index)) as c:
        yield c


def stream(device_id: str, sensor: str, data: dict, key: str = DEVICE_KEY) -> dict:
    return {"device_id": device_id, "sensor": sensor, "data": data, "api_key": key}
# Jeevan sync: 2026-11-13

from __future__ import annotations

from app import triage
from app.config import Settings
from app.hub import Hub
from app.rag.bm25 import tokenize
from app.rag.chunker import chunk_markdown
from app.rag.index import HybridIndex


def hub(**kw) -> Hub:
    return Hub(Settings(_env_file=None, **kw))


def test_triage_levels():
    assert triage.analyze(72, 98, 36.8)["overall_status"] == "normal"
    assert triage.analyze(130, 98, 36.8)["overall_status"] == "warning"
    crit = triage.analyze(72, 85, 36.8)
    assert crit["overall_status"] == "critical" and crit["risk_score"] >= 90
    assert triage.analyze()["summary"] == "Waiting for sensor data."


def test_hub_merges_sensors_and_expires_stale():
    h = hub()
    h.ingest_stream("d1", "max30102", {"finger_detected": True, "heart_rate": 80, "heart_rate_valid": True, "spo2": 97, "spo2_valid": True}, now=1000)
    snap = h.ingest_stream("d1", "dht11", {"valid": True, "temperature": 36.84}, now=1002)
    assert snap["vitals"]["heart_rate"] == 80 and snap["vitals"]["temperature"] == 36.8
    # 61 s later (> metric_ttl_s) everything is stale
    assert h.snapshot("d1", now=1063)["vitals"] == {}


def test_invalid_or_no_finger_does_not_publish_zero_readings():
    h = hub()
    h.ingest_stream("d1", "max30102", {"finger_detected": True, "heart_rate": 80, "heart_rate_valid": True}, now=1)
    snap = h.ingest_stream("d1", "max30102", {"finger_detected": False, "heart_rate": 0, "heart_rate_valid": False}, now=2)
    assert "heart_rate" not in snap["vitals"]
    snap = h.ingest_stream("d1", "ad8232", {"lead_off": True, "ecg_bpm": 70, "ecg_bpm_valid": True}, now=3)
    assert snap["vitals"]["lead_off"] is True and "ecg_bpm" not in snap["vitals"]


def test_sensor_rotation_and_pin():
    h = hub()
    assert h.next_command("d", now=100) == "read_max30102"
    assert h.next_command("d", now=114) == "read_max30102"
    assert h.next_command("d", now=115) == "read_dht11"
    assert h.next_command("d", now=119) == "read_ad8232"
    assert h.next_command("d", now=125) == "read_max30102"
    h.set_command("d", "read_ad8232")
    assert h.next_command("d", now=500) == "read_ad8232"
    h.set_command("d", "auto")
    assert h.next_command("d", now=501) in {"read_max30102", "read_dht11", "read_ad8232"}


def test_pairing_is_exclusive():
    h = hub()
    assert h.pair("d", "u1") and h.pair("d", "u1")
    assert not h.pair("d", "u2")
    assert h.unpair("d", "u1") and h.pair("d", "u2")


def test_publish_only_reaches_owner_and_drops_oldest_when_full():
    h = hub()
    h.pair("d", "u1")
    mine, other = h.subscribe("u1"), h.subscribe("u2")
    h.ingest_stream("d", "dht11", {"valid": True, "temperature": 36.5})
    assert mine.queue.qsize() == 1 and other.queue.qsize() == 0
    for i in range(400):
        mine.push({"type": "x", "i": i})
    assert mine.queue.qsize() == 256
    assert mine.queue.get_nowait()["i"] >= 100 or mine.queue.get_nowait()["i"] >= 100


def test_bm25_retrieval_finds_right_topic():
    idx = HybridIndex()
    idx.build_shared()
    assert idx.shared, "knowledge base should load"
    top = idx.search("how do I do CPR on someone not breathing", k=3)
    assert any("cpr" in h.chunk.source.lower() or "CPR" in h.chunk.heading for h in top)
    top = idx.search("my blood sugar is low and I'm shaky", k=3)
    assert any("sugar" in h.chunk.text.lower() or "hypoglyc" in h.chunk.text.lower() for h in top)
    top = idx.search("what to do for a snake bite", k=2)
    assert any("snake" in h.chunk.heading.lower() for h in top)


def test_user_documents_are_private():
    idx = HybridIndex()
    idx.build_shared()
    idx.set_user_documents("alice", [("Prescription", "Alice takes zorbitan 40mg nightly for her condition.")])
    assert any(h.chunk.owner == "alice" for h in idx.search("zorbitan dose", user_id="alice"))
    assert not any(h.chunk.owner for h in idx.search("zorbitan dose", user_id="bob"))
    assert not any(h.chunk.owner for h in idx.search("zorbitan dose"))


def test_tokenizer_stems_and_chunker_splits():
    assert tokenize("Bleeding burns") == ["bleed", "burn"]
    long = "# T\n## H\n" + " ".join(f"w{i}" for i in range(500))
    chunks = chunk_markdown("Doc", long)
    assert len(chunks) > 2 and all(c.heading == "T > H" for c in chunks)


def test_agora_rtc_token_builder():
    from app.agora import build_rtc_token

    res = build_rtc_token(
        app_id="a" * 32,
        app_certificate="b" * 32,
        channel_id="emergency-room-123",
        uid="user-42",
        role="publisher",
        expires_in_seconds=1800,
    )
    assert res["token"].startswith("007")
    assert res["channelId"] == "emergency-room-123"
    assert res["uid"] == "user-42"
    assert res["role"] == "publisher"



"""Health Vault: document storage routed through FastAPI (bypasses RLS via service-role key)."""
from __future__ import annotations

import uuid
from datetime import datetime, timezone
from typing import Any, Optional

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, Field

from ..ctx import Context, get_ctx
from ..security import User, current_user

router = APIRouter(prefix="/api/health-vault", tags=["health-vault"])


class DocumentBody(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    category: str = Field(min_length=1, max_length=50)
    description: Optional[str] = None
    document_date: Optional[str] = None
    doctor_name: Optional[str] = None
    hospital_name: Optional[str] = None
    tags: list[str] = Field(default_factory=list)
    file_url: Optional[str] = None
    file_name: Optional[str] = None
    file_size: Optional[int] = None
    file_type: Optional[str] = None


@router.get("/documents")
async def list_documents(request: Request, user: User = Depends(current_user)) -> dict[str, Any]:
    ctx = get_ctx(request)
    try:
        rows = await ctx.persist.select_required(
            "health_documents",
            {"user_id": f"eq.{user.id}", "order": "created_at.desc"},
        )
    except RuntimeError as exc:
        raise HTTPException(
            503,
            "Health Vault storage is unavailable. Apply supabase/010_health_vault_reliability.sql and verify the backend Supabase service key.",
        ) from exc
    return {"documents": rows}


@router.post("/documents", status_code=201)
async def create_document(body: DocumentBody, request: Request, user: User = Depends(current_user)) -> dict[str, Any]:
    ctx = get_ctx(request)
    doc = {
        "id": str(uuid.uuid4()),
        "user_id": user.id,
        "title": body.title,
        "category": body.category,
        **({"description": body.description} if body.description else {}),
        **({"document_date": body.document_date} if body.document_date else {}),
        **({"doctor_name": body.doctor_name} if body.doctor_name else {}),
        **({"hospital_name": body.hospital_name} if body.hospital_name else {}),
        **({"tags": body.tags} if body.tags else {}),
        **({"file_url": body.file_url} if body.file_url else {}),
        **({"file_name": body.file_name} if body.file_name else {}),
        **({"file_size": body.file_size} if body.file_size is not None else {}),
        **({"file_type": body.file_type} if body.file_type else {}),
    }
    ok = await ctx.persist.insert("health_documents", doc)
    if not ok:
        raise HTTPException(
            503,
            "Document could not be saved. Apply supabase/010_health_vault_reliability.sql and verify the backend Supabase service key.",
        )
    return {"status": "created", "document": doc}


@router.delete("/documents/{doc_id}")
async def delete_document(doc_id: str, request: Request, user: User = Depends(current_user)) -> dict[str, str]:
    ctx = get_ctx(request)
    ctx.spawn(ctx.persist._send("DELETE", "health_documents", params={"id": f"eq.{doc_id}", "user_id": f"eq.{user.id}"}))
    return {"status": "deleted"}


# ── Vault Settings ──
class VaultPasswordBody(BaseModel):
    vault_password_hash: str = Field(min_length=1, max_length=200)


@router.get("/settings")
async def get_vault_settings(request: Request, user: User = Depends(current_user)) -> dict[str, Any]:
    ctx = get_ctx(request)
    try:
        rows = await ctx.persist.select_required(
            "vault_settings", {"user_id": f"eq.{user.id}", "limit": "1"}
        )
    except RuntimeError as exc:
        raise HTTPException(
            503,
            "Health Vault settings are unavailable. Apply supabase/010_health_vault_reliability.sql and verify the backend Supabase service key.",
        ) from exc
    return {"settings": rows[0] if rows else None}


@router.post("/settings/password")
async def set_vault_password(body: VaultPasswordBody, request: Request, user: User = Depends(current_user)) -> dict[str, str]:
    ctx = get_ctx(request)
    saved = await ctx.persist.upsert("vault_settings", {
        "user_id": user.id,
        "vault_password_hash": body.vault_password_hash,
        "is_vault_locked": True,
    }, "user_id")
    if not saved:
        raise HTTPException(
            503,
            "Vault password was not saved. Apply supabase/010_health_vault_reliability.sql and verify the backend Supabase service key.",
        )
    return {"status": "saved"}


# ── Emergency Contacts ──
class ContactBody(BaseModel):
    name: str = Field(min_length=1, max_length=100)
    phone: str = Field(min_length=1, max_length=20)
    relationship: str = "Other"
    is_primary: bool = False


@router.get("/contacts")
async def list_contacts(request: Request, user: User = Depends(current_user)) -> dict[str, Any]:
    ctx = get_ctx(request)
    rows = await ctx.persist.select("emergency_contacts", {"user_id": f"eq.{user.id}", "order": "created_at.desc"})
    return {"contacts": rows}


@router.post("/contacts", status_code=201)
async def add_contact(body: ContactBody, request: Request, user: User = Depends(current_user)) -> dict[str, Any]:
    ctx = get_ctx(request)
    contact = {
        "id": str(uuid.uuid4()),
        "user_id": user.id,
        "name": body.name,
        "phone": body.phone,
        "relationship": body.relationship,
        "is_primary": body.is_primary,
    }
    ok = await ctx.persist.insert("emergency_contacts", contact)
    if not ok:
        raise HTTPException(500, "Failed to store contact")
    return {"status": "created", "contact": contact}


@router.delete("/contacts/{contact_id}")
async def delete_contact(contact_id: str, request: Request, user: User = Depends(current_user)) -> dict[str, str]:
    ctx = get_ctx(request)
    ctx.spawn(ctx.persist._send("DELETE", "emergency_contacts", params={"id": f"eq.{contact_id}", "user_id": f"eq.{user.id}"}))
    return {"status": "deleted"}


# ── MediScan Results ──
@router.get("/scans")
async def list_scans(request: Request, user: User = Depends(current_user)) -> dict[str, Any]:
    ctx = get_ctx(request)
    rows = await ctx.persist.select("mediscan_results", {"user_id": f"eq.{user.id}", "order": "created_at.desc"})
    return {"scans": rows}


@router.post("/scans", status_code=201)
async def save_scan(request: Request, user: User = Depends(current_user)) -> dict[str, Any]:
    ctx = get_ctx(request)
    try:
        body = await request.json()
    except ValueError:
        raise HTTPException(400, "Body must be valid JSON")
    scan = {
        "id": str(uuid.uuid4()),
        "user_id": user.id,
        **{k: v for k, v in body.items() if k in ("scan_type", "original_image_url", "extracted_data", "ai_analysis", "confidence_score", "status")},
    }
    scan.setdefault("status", "completed")
    ok = await ctx.persist.insert("mediscan_results", scan)
    if not ok:
        raise HTTPException(500, "Failed to store scan result")
    return {"status": "created", "scan": scan}


@router.delete("/scans/{scan_id}")
async def delete_scan(scan_id: str, request: Request, user: User = Depends(current_user)) -> dict[str, str]:
    ctx = get_ctx(request)
    ctx.spawn(ctx.persist._send("DELETE", "mediscan_results", params={"id": f"eq.{scan_id}", "user_id": f"eq.{user.id}"}))
    return {"status": "deleted"}


# ── Symptom Checks ──
@router.get("/symptom-checks")
async def list_symptom_checks(request: Request, user: User = Depends(current_user)) -> dict[str, Any]:
    ctx = get_ctx(request)
    rows = await ctx.persist.select("symptom_checks", {"user_id": f"eq.{user.id}", "order": "created_at.desc"})
    return {"checks": rows}


@router.post("/symptom-checks", status_code=201)
async def save_symptom_check(request: Request, user: User = Depends(current_user)) -> dict[str, Any]:
    ctx = get_ctx(request)
    try:
        body = await request.json()
    except ValueError:
        raise HTTPException(400, "Body must be valid JSON")
    check = {
        "id": str(uuid.uuid4()),
        "user_id": user.id,
        **{k: v for k, v in body.items() if k in ("symptoms", "body_region", "severity", "duration", "ai_diagnosis", "recommended_actions", "urgency_level")},
    }
    ok = await ctx.persist.insert("symptom_checks", check)
    if not ok:
        raise HTTPException(500, "Failed to store symptom check")
    return {"status": "created", "check": check}


# ── Community Alerts ──
@router.get("/alerts")
async def list_alerts(request: Request, user: User = Depends(current_user)) -> dict[str, Any]:
    ctx = get_ctx(request)
    rows = await ctx.persist.select(
        "community_alerts",
        {"user_id": f"eq.{user.id}", "order": "created_at.desc"},
    )
    return {"alerts": rows}


class AlertBody(BaseModel):
    alert_type: str = Field(min_length=1, max_length=50)
    latitude: float = 0.0
    longitude: float = 0.0
    address: str = ""
    title: str = ""


@router.post("/alerts", status_code=201)
async def create_alert(body: AlertBody, request: Request, user: User = Depends(current_user)) -> dict[str, Any]:
    ctx = get_ctx(request)
    alert = {
        "id": str(uuid.uuid4()),
        "user_id": user.id,
        "alert_type": body.alert_type,
        "latitude": body.latitude,
        "longitude": body.longitude,
        "address": body.address,
        "title": body.title,
        "status": "active",
    }
    ok = await ctx.persist.insert("community_alerts", alert)
    if not ok:
        raise HTTPException(500, "Failed to store alert")
    return {"status": "created", "alert": alert}


# ── Profiles ──
@router.get("/profile")
async def get_profile(request: Request, user: User = Depends(current_user)) -> dict[str, Any]:
    ctx = get_ctx(request)
    rows = await ctx.persist.select("profiles", {"id": f"eq.{user.id}", "limit": "1"})
    return {"profile": rows[0] if rows else None}


@router.patch("/profile")
async def update_profile(request: Request, user: User = Depends(current_user)) -> dict[str, Any]:
    ctx = get_ctx(request)
    try:
        body = await request.json()
    except ValueError:
        raise HTTPException(400, "Body must be valid JSON")
    safe_fields = {k: v for k, v in body.items() if k in ("name", "phone", "blood_type", "dob", "gender", "address", "avatar_url")}
    if not safe_fields:
        raise HTTPException(400, "No valid fields to update")
    ok = await ctx.persist.update("profiles", {"id": user.id}, safe_fields)
    if not ok:
        # Try upsert if profile doesn't exist yet
        await ctx.persist.upsert("profiles", {"id": user.id, **safe_fields}, "id")
    return {"status": "updated"}


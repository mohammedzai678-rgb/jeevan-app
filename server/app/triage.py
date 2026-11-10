"""Rule-based vitals triage (port of backend/src/services/vitawatchAnalysis.ts, rule engine only).

Pure and allocation-light so it can run on every live sample (microseconds) without touching an LLM.
"""
from __future__ import annotations

from datetime import datetime, timezone
from typing import Any, Optional

DISCLAIMER = (
    "Jeevan provides automated vitals evaluation for informational awareness. It is not a clinical "
    "diagnosis. In an emergency call your local emergency number immediately."
)

_ORDER = {"normal": 0, "attention": 1, "warning": 2, "critical": 3}


def _finding(metric: str, value: str, status: str, normal: str, why: str, rec: str) -> dict[str, str]:
    return {
        "metric": metric,
        "value": value,
        "status": status,
        "normal_range": normal,
        "explanation": why,
        "recommendation": rec,
    }


def analyze(
    heart_rate: Optional[float] = None,
    spo2: Optional[float] = None,
    temperature: Optional[float] = None,
    ecg_bpm: Optional[float] = None,
    lead_off: bool = False,
    systolic_bp: Optional[float] = None,
    diastolic_bp: Optional[float] = None,
) -> dict[str, Any]:
    findings: list[dict[str, str]] = []
    red_flags: list[str] = []
    counts = {"critical": 0, "warning": 0, "attention": 0}

    def bump(level: str, weight: int = 1) -> None:
        if level in counts:
            counts[level] += weight

    if heart_rate:
        hr = int(heart_rate)
        status, why, rec = "normal", "Heart rate is within the typical adult resting range.", "No action needed."
        if hr < 40 or hr > 150:
            status = "critical"
            why = f"Severe {'bradycardia' if hr < 40 else 'tachycardia'} ({hr} BPM)."
            rec = "Seek urgent medical attention. Sit or lie down and rest."
            red_flags.append(f"Critical heart rate: {hr} BPM")
        elif hr < 50 or hr > 120:
            status = "warning"
            why = f"Marked {'bradycardia' if hr < 50 else 'tachycardia'} ({hr} BPM)."
            rec = "Rest, hydrate, avoid stimulants and recheck in 10 minutes."
            red_flags.append(f"Abnormal heart rate: {hr} BPM")
        elif hr > 100 or hr < 60:
            status = "attention"
            why = f"Mildly {'elevated' if hr > 100 else 'low'} resting heart rate ({hr} BPM)."
            rec = "Relax, breathe slowly and recheck at rest."
        bump(status)
        findings.append(_finding("Heart Rate", f"{hr} BPM", status, "60-100 BPM", why, rec))

    if spo2:
        s = int(spo2)
        status, why, rec = "normal", "Blood oxygen saturation is optimal.", "No action needed."
        if s < 90:
            status = "critical"
            why = f"Severe hypoxemia ({s}%)."
            rec = "Seek urgent medical attention. Sit upright and avoid exertion."
            red_flags.append(f"Severe hypoxemia: SpO2 {s}%")
            bump("critical", 2)
        elif s < 94:
            status = "warning"
            why = f"Low oxygen saturation ({s}%). Could also be poor sensor contact."
            rec = "Sit upright, breathe deeply, warm and clean the finger, and rescan."
            red_flags.append(f"Low SpO2: {s}%")
            bump("warning")
        elif s < 95:
            status = "attention"
            why = f"Borderline saturation ({s}%)."
            rec = "Keep an upright posture and monitor closely."
            bump("attention")
        findings.append(_finding("SpO2", f"{s}%", status, "95-100%", why, rec))

    if temperature:
        t = float(temperature)
        status, why, rec = "normal", f"Body temperature ({t:.1f} °C) is in the normal range.", "No action needed."
        if t >= 40.0 or t < 34.0:
            status = "critical"
            why = f"{'Hyperthermia' if t >= 40 else 'Hypothermia'} range ({t:.1f} °C)."
            rec = "Seek emergency care. Cool or rewarm gradually while waiting."
            red_flags.append(f"Critical temperature: {t:.1f} °C")
        elif t >= 38.5 or t < 35.5:
            status = "warning"
            why = f"{'Fever' if t >= 38.5 else 'Subnormal temperature'} ({t:.1f} °C)."
            rec = "Rest and drink fluids; monitor for other symptoms."
            red_flags.append(f"{'Fever' if t >= 38.5 else 'Low temperature'}: {t:.1f} °C")
        elif t >= 37.5 or t < 36.0:
            status = "attention"
            why = f"Slightly {'raised' if t >= 37.5 else 'low'} temperature ({t:.1f} °C)."
            rec = "Hydrate and recheck in a few hours."
        bump(status)
        findings.append(_finding("Temperature", f"{t:.1f} °C", status, "36.1-37.2 °C", why, rec))

    if lead_off:
        bump("attention")
        findings.append(
            _finding(
                "ECG", "LEADS OFF", "attention", "n/a",
                "ECG electrodes are disconnected.", "Attach the electrodes firmly to the skin.",
            )
        )
    elif ecg_bpm:
        e = int(ecg_bpm)
        status, why, rec = "normal", "ECG rate is regular.", "No action needed."
        if e < 45 or e > 145:
            status = "critical"
            why = f"Marked ECG rate abnormality ({e} BPM)."
            rec = "Check electrode placement; if the pulse is confirmed abnormal seek a clinical ECG."
            red_flags.append(f"ECG rate abnormality: {e} BPM")
        elif heart_rate and abs(e - heart_rate) > 20:
            status = "warning"
            why = f"PPG heart rate ({int(heart_rate)}) and ECG rate ({e}) disagree."
            rec = "Check for motion artefact, tremor or loose sensors."
            red_flags.append(f"Pulse/ECG mismatch: {int(heart_rate)} vs {e}")
        bump(status)
        findings.append(_finding("ECG", f"{e} BPM", status, "60-100 BPM", why, rec))

    if systolic_bp and diastolic_bp:
        sy, di = int(systolic_bp), int(diastolic_bp)
        status, why, rec = "normal", f"Blood pressure ({sy}/{di}) is normal.", "No action needed."
        if sy >= 180 or di >= 120:
            status = "critical"
            why = f"Hypertensive crisis range ({sy}/{di})."
            rec = "Seek emergency care, especially with headache, chest pain or vision changes."
            red_flags.append(f"Hypertensive crisis: {sy}/{di}")
            bump("critical", 2)
        elif sy >= 140 or di >= 90:
            status = "warning"
            why = f"Stage 2 hypertension range ({sy}/{di})."
            rec = "Consult a physician; reduce salt and stress."
            red_flags.append(f"High blood pressure: {sy}/{di}")
            bump("warning")
        elif sy >= 130 or di >= 80:
            status = "attention"
            why = f"Elevated blood pressure ({sy}/{di})."
            rec = "Monitor regularly."
            bump("attention")
        elif sy < 90 or di < 60:
            status = "warning"
            why = f"Low blood pressure ({sy}/{di})."
            rec = "Hydrate and rise slowly."
            red_flags.append(f"Low blood pressure: {sy}/{di}")
            bump("warning")
        findings.append(_finding("Blood Pressure", f"{sy}/{di} mmHg", status, "<120/<80", why, rec))

    if counts["critical"]:
        overall, risk = "critical", min(85 + counts["critical"] * 5, 100)
        summary = f"Critical: {counts['critical']} high-risk parameter(s). Seek medical help now."
    elif counts["warning"]:
        overall, risk = "warning", min(55 + counts["warning"] * 10, 80)
        summary = f"{counts['warning']} metric(s) outside the normal range. Rest and recheck shortly."
    elif counts["attention"]:
        overall, risk = "attention", 35
        summary = "Minor deviations from baseline. Rest and recheck."
    elif findings:
        overall, risk = "normal", 10
        summary = "All measured vitals are within normal resting ranges."
    else:
        overall, risk = "normal", 0
        summary = "Waiting for sensor data."

    return {
        "overall_status": overall,
        "risk_score": risk,
        "summary": summary,
        "findings": findings,
        "red_flags": red_flags,
        "analyzed_at": datetime.now(timezone.utc).isoformat(),
        "ai_provider": "rule_engine",
        "disclaimer": DISCLAIMER,
    }


def worst(a: str, b: str) -> str:
    return a if _ORDER.get(a, 0) >= _ORDER.get(b, 0) else b

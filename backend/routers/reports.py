import io
from datetime import datetime, date, timedelta
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException, Query, Header
from fastapi.responses import StreamingResponse
from sqlalchemy.orm import Session
from reportlab.lib.pagesizes import A4, landscape
from reportlab.lib import colors
from reportlab.lib.units import inch
from reportlab.platypus import (
    SimpleDocTemplate, Table, TableStyle, Paragraph, Spacer, Flowable, PageBreak, Image,
)
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.graphics.shapes import Drawing, PolyLine, String, Line
from reportlab.graphics import renderPDF

from database import get_db
from auth import verify_token
from audit_service import staff_display_name
from report_export import stream_csv, stream_xlsx, stream_xlsx_with_proofs, _escape_xml
from models import (
    User, Profile, Doctor, Appointment, MedicalRecord,
    Prescription, PrescriptionItem, SensorData, ClinicSettings, Payment, AuditLog,
)
from time_format import format_time_12h

router = APIRouter()

UPLOADS_DIR = Path(__file__).resolve().parent.parent / "uploads"


def _proof_file_path(relative_url: str | None) -> Path | None:
    if not relative_url:
        return None
    name = relative_url.strip().lstrip("/")
    if name.startswith("uploads/"):
        name = name[len("uploads/"):]
    path = UPLOADS_DIR / Path(name).name
    return path if path.is_file() else None


def _proof_label(payment: Payment, db: Session, *, kind: str = "payment") -> str:
    apt = db.query(Appointment).filter(Appointment.id == payment.appointment_id).first()
    patient = db.query(Profile).filter(Profile.id == apt.patient_id).first() if apt else None
    patient_name = f"{patient.first_name} {patient.last_name}".strip() if patient else "N/A"
    invoice = f"INV-{payment.id[:8].upper()}"
    apt_date = str(apt.date) if apt and apt.date else "-"
    if kind == "refund":
        refunded_at = payment.refunded_at.strftime("%Y-%m-%d %H:%M") if payment.refunded_at else "-"
        return (
            f"{invoice} — {patient_name} — {payment.amount:.0f} EGP refunded — "
            f"{payment.refund_reason or 'No reason'} — {refunded_at}"
        )
    return (
        f"{invoice} — {patient_name} — {payment.amount:.0f} EGP — "
        f"{payment.payment_method or 'N/A'} ({payment.payment_status}) — {apt_date}"
    )


def _scale_report_image(img: Image, max_width: float, max_height: float) -> None:
    iw, ih = img.imageWidth, img.imageHeight
    if iw <= 0 or ih <= 0:
        img.drawWidth = min(max_width, 400)
        img.drawHeight = min(max_height, 300)
        return
    scale = min(max_width / iw, max_height / ih, 1.0)
    img.drawWidth = iw * scale
    img.drawHeight = ih * scale


def _proof_image_elements(
    caption: str,
    relative_url: str | None,
    *,
    caption_style: ParagraphStyle,
    body_style: ParagraphStyle,
    max_width: float,
    max_height: float = 380,
) -> list:
    elements: list = [Paragraph(_escape_xml(caption), caption_style)]
    path = _proof_file_path(relative_url)
    if path and path.suffix.lower() in (".jpg", ".jpeg", ".png", ".gif", ".webp", ".bmp"):
        img = Image(str(path))
        _scale_report_image(img, max_width, max_height)
        elements.append(Spacer(1, 4))
        elements.append(img)
    elif path:
        elements.append(Paragraph(f"Proof file on record (non-image): {_escape_xml(relative_url or '')}", body_style))
    else:
        ref = relative_url or "none"
        elements.append(Paragraph(f"Proof reference: {_escape_xml(ref)} (file not found on server)", body_style))
    elements.append(Spacer(1, 14))
    return elements


def _append_payment_proof_gallery(
    elements: list,
    payments: list[Payment],
    db: Session,
    subtitle_style: ParagraphStyle,
    caption_style: ParagraphStyle,
    body_style: ParagraphStyle,
    max_width: float,
    max_height: float = 380,
) -> None:
    proof_items = [p for p in payments if p.proof_url]
    if not proof_items:
        return
    elements.append(PageBreak())
    elements.append(Paragraph("Payment Proof Screenshots", subtitle_style))
    elements.append(Paragraph(
        "InstaPay and other payment confirmations attached at time of recording.",
        body_style,
    ))
    elements.append(Spacer(1, 8))
    for payment in proof_items:
        elements.extend(_proof_image_elements(
            _proof_label(payment, db, kind="payment"),
            payment.proof_url,
            caption_style=caption_style,
            body_style=body_style,
            max_width=max_width,
            max_height=max_height,
        ))


def _append_refund_proof_gallery(
    elements: list,
    payments: list[Payment],
    db: Session,
    subtitle_style: ParagraphStyle,
    caption_style: ParagraphStyle,
    body_style: ParagraphStyle,
    max_width: float,
    max_height: float = 380,
) -> None:
    proof_items = [p for p in payments if p.refund_proof_url]
    if not proof_items:
        return
    elements.append(PageBreak())
    elements.append(Paragraph("Refund Proof Screenshots", subtitle_style))
    elements.append(Paragraph(
        "Refund confirmation screenshots submitted by reception staff.",
        body_style,
    ))
    elements.append(Spacer(1, 8))
    for payment in proof_items:
        elements.extend(_proof_image_elements(
            _proof_label(payment, db, kind="refund"),
            payment.refund_proof_url,
            caption_style=caption_style,
            body_style=body_style,
            max_width=max_width,
            max_height=max_height,
        ))


def _resolve_token(
    token: str | None,
    authorization: str | None,
) -> str:
    if token:
        return token
    if authorization and authorization.lower().startswith("bearer "):
        return authorization[7:].strip()
    raise HTTPException(status_code=401, detail="Authentication token required")


def _get_user_from_token(token: str, db: Session) -> User:
    payload = verify_token(token, expected_type="access")
    user = db.query(User).filter(User.id == payload.get("sub")).first()
    if not user:
        raise HTTPException(status_code=401, detail="User not found")
    if not user.is_active:
        raise HTTPException(status_code=403, detail="Account is deactivated")
    return user


def _get_report_user(
    token: str | None = Query(None),
    authorization: str | None = Header(None),
    db: Session = Depends(get_db),
) -> User:
    access = _resolve_token(token, authorization)
    return _get_user_from_token(access, db)


def _require_roles(user: User, *roles: str) -> None:
    if user.role not in roles:
        raise HTTPException(status_code=403, detail="Not authorized to access this report")


def _get_clinic_name(db: Session) -> str:
    settings = db.query(ClinicSettings).first()
    return settings.clinic_name if settings else "Octocare Clinic"


def _doctor_display_name(db: Session, doctor_id: str) -> str:
    doctor = db.query(Doctor).filter(Doctor.id == doctor_id).first()
    if not doctor:
        return "N/A"
    profile = db.query(Profile).filter(Profile.id == doctor.profile_id).first()
    if profile:
        return f"Dr. {profile.first_name or ''} {profile.last_name or ''}".strip()
    return "N/A"


def _profile_display_name(db: Session, profile_id: str) -> str:
    profile = db.query(Profile).filter(Profile.id == profile_id).first()
    if profile:
        return f"{profile.first_name or ''} {profile.last_name or ''}".strip()
    return "Staff"


def _header_footer(canvas, doc, clinic_name: str):
    page_w, page_h = doc.pagesize
    canvas.saveState()
    canvas.setFont("Helvetica-Bold", 14)
    canvas.drawString(40, page_h - 40, clinic_name)
    canvas.setFont("Helvetica", 9)
    canvas.drawRightString(
        page_w - 40, page_h - 40,
        f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M')}",
    )
    canvas.line(40, page_h - 50, page_w - 40, page_h - 50)
    canvas.setFont("Helvetica", 8)
    canvas.drawString(40, 25, f"Page {doc.page}")
    canvas.drawRightString(page_w - 40, 25, f"© {datetime.now().year} {clinic_name}")
    canvas.restoreState()


def _build_table(data: list[list], col_widths=None, wrap_body: bool = False) -> Table:
    styles = getSampleStyleSheet()
    header_style = ParagraphStyle(
        "TblHeader",
        parent=styles["Normal"],
        fontName="Helvetica-Bold",
        fontSize=8,
        leading=10,
        textColor=colors.white,
    )
    body_style = ParagraphStyle(
        "TblBody",
        parent=styles["Normal"],
        fontSize=7,
        leading=9,
    )

    table_data: list[list] = []
    for r_idx, row in enumerate(data):
        if wrap_body and r_idx > 0:
            table_data.append([Paragraph(_escape_xml(str(c)), body_style) for c in row])
        elif wrap_body and r_idx == 0:
            table_data.append([Paragraph(_escape_xml(str(c)), header_style) for c in row])
        else:
            table_data.append(row)

    style = TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#2c3e50")),
        ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
        ("ALIGN", (0, 0), (-1, -1), "LEFT"),
        ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
        ("FONTSIZE", (0, 0), (-1, 0), 8),
        ("BOTTOMPADDING", (0, 0), (-1, 0), 8),
        ("TOPPADDING", (0, 0), (-1, 0), 8),
        ("BACKGROUND", (0, 1), (-1, -1), colors.HexColor("#ecf0f1")),
        ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, colors.HexColor("#f8f9fa")]),
        ("GRID", (0, 0), (-1, -1), 0.5, colors.HexColor("#bdc3c7")),
        ("FONTSIZE", (0, 1), (-1, -1), 7),
        ("TOPPADDING", (0, 1), (-1, -1), 5),
        ("BOTTOMPADDING", (0, 1), (-1, -1), 5),
        ("LEFTPADDING", (0, 0), (-1, -1), 4),
        ("RIGHTPADDING", (0, 0), (-1, -1), 4),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
    ])
    table = Table(table_data, colWidths=col_widths, repeatRows=1)
    table.setStyle(style)
    return table


def _pdf_stream(buf: io.BytesIO, filename: str) -> StreamingResponse:
    buf.seek(0)
    return StreamingResponse(
        buf,
        media_type="application/pdf",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


def _normalize_format(fmt: str) -> str:
    normalized = (fmt or "pdf").lower().strip()
    if normalized not in ("pdf", "csv", "xlsx"):
        raise HTTPException(status_code=400, detail="format must be pdf, csv, or xlsx")
    return normalized


class _ChartFlowable(Flowable):
    def __init__(self, drawing: Drawing, width: float, height: float):
        self.drawing = drawing
        self.width = width
        self.height = height

    def wrap(self, availWidth, availHeight):
        return self.width, self.height

    def draw(self):
        renderPDF.draw(self.drawing, self.canv, 0, 0)


def _make_line_chart(
    title: str,
    description: str,
    points: list[tuple[str, float]],
    ylabel: str,
    color: str,
) -> Drawing:
    width, chart_height = 460, 110
    total_height = chart_height + 54
    d = Drawing(width, total_height)
    d.add(String(0, total_height - 18, title, fontSize=11, fillColor=colors.HexColor("#2c3e50")))
    d.add(String(0, total_height - 32, description, fontSize=8, fillColor=colors.grey))

    if not points:
        d.add(String(0, 40, "No data", fontSize=9))
        return d

    values = [v for _, v in points]
    labels = [lbl for lbl, _ in points]
    min_v = min(values)
    max_v = max(values)
    spread = max(max_v - min_v, 1.0)
    pad = spread * 0.12
    min_y = min_v - pad
    max_y = max_v + pad

    x0, y0 = 48, 14
    plot_w = width - 62
    plot_h = chart_height - 12

    d.add(Line(x0, y0, x0, y0 + plot_h, strokeColor=colors.HexColor("#bdc3c7")))
    d.add(Line(x0, y0, x0 + plot_w, y0, strokeColor=colors.HexColor("#bdc3c7")))
    d.add(String(2, y0 + plot_h / 2, ylabel, fontSize=7, fillColor=colors.grey))

    for tick in range(5):
        frac = tick / 4
        y_val = min_y + frac * (max_y - min_y)
        y = y0 + frac * plot_h
        d.add(String(2, y - 3, f"{y_val:.1f}", fontSize=6, fillColor=colors.grey))
        d.add(Line(x0, y, x0 + plot_w, y, strokeColor=colors.HexColor("#ecf0f1"), strokeWidth=0.5))

    poly_points: list[float] = []
    n = len(values)
    for i, (label, v) in enumerate(zip(labels, values)):
        x = x0 + (i / max(n - 1, 1)) * plot_w
        y = y0 + ((v - min_y) / (max_y - min_y)) * plot_h
        poly_points.extend([x, y])
        d.add(String(x - 8, y + 4, f"{v:.1f}", fontSize=6, fillColor=colors.HexColor(color)))
        short_label = label if len(label) <= 10 else label[:9] + "…"
        d.add(String(x - 10, y0 - 10, short_label, fontSize=5, fillColor=colors.grey))

    if len(poly_points) >= 4:
        d.add(PolyLine(poly_points, strokeColor=colors.HexColor(color), strokeWidth=1.8))

    d.add(String(x0, 0, "Oldest reading → newest (left to right)", fontSize=7, fillColor=colors.grey))
    return d


def _generate_patient_report(profile, db: Session):
    clinic_name = _get_clinic_name(db)
    styles = getSampleStyleSheet()
    title_style = ParagraphStyle("Title2", parent=styles["Title"], fontSize=16, spaceAfter=12)
    subtitle_style = ParagraphStyle(
        "Sub", parent=styles["Heading3"], fontSize=11, spaceAfter=6, textColor=colors.HexColor("#2c3e50")
    )
    body_style = ParagraphStyle("BodySmall", parent=styles["Normal"], fontSize=9, spaceAfter=4)

    buf = io.BytesIO()
    doc = SimpleDocTemplate(buf, pagesize=A4, topMargin=70, bottomMargin=50)
    elements = []

    elements.append(Paragraph(f"Patient Report: {profile.first_name} {profile.last_name}", title_style))
    elements.append(Spacer(1, 6))

    appointments = (
        db.query(Appointment)
        .filter(Appointment.patient_id == profile.id)
        .order_by(Appointment.date.desc(), Appointment.time_slot.desc())
        .all()
    )
    visit_count = sum(1 for a in appointments if a.status in ("completed", "arrived", "confirmed"))

    info_data = [
        ["Field", "Value"],
        ["Name", f"{profile.first_name} {profile.last_name}"],
        ["Date of Birth", str(profile.dob or "N/A")],
        ["Gender", profile.gender or "N/A"],
        ["Phone", profile.phone or "N/A"],
        ["Blood Type", profile.blood_type or "N/A"],
        ["Allergies", profile.allergies or "None"],
        ["Chronic Diseases", profile.chronic_diseases or "None"],
        ["Medications (patient reported)", profile.existing_conditions or "None"],
        ["Clinic Visits", str(visit_count)],
        ["Emergency Contact", f"{profile.emergency_contact_name or 'N/A'} ({profile.emergency_contact_phone or 'N/A'})"],
    ]
    elements.append(_build_table(info_data, col_widths=[2.2 * inch, 3.8 * inch], wrap_body=True))
    elements.append(Spacer(1, 14))

    elements.append(Paragraph("Consultations & Reservations", subtitle_style))
    consult_data = [["Date", "Time", "Doctor", "Receptionist", "Diagnosis", "Notes", "Paid", "Status"]]
    for apt in appointments[:25]:
        payment = db.query(Payment).filter(Payment.appointment_id == apt.id).first()
        record = (
            db.query(MedicalRecord)
            .filter(MedicalRecord.appointment_id == apt.id, MedicalRecord.is_active == True)
            .first()
        )
        receptionist = (
            _profile_display_name(db, payment.receptionist_id)
            if payment and payment.receptionist_id
            else "-"
        )
        paid = "-"
        if payment:
            paid = f"{payment.amount} ({payment.payment_method or 'N/A'})"
        notes_parts = [n for n in [apt.notes, record.notes if record else None] if n]
        consult_data.append([
            str(apt.date or "-"),
            format_time_12h(apt.time_slot),
            _doctor_display_name(db, apt.doctor_id),
            receptionist,
            (record.diagnosis if record else "-")[:35],
            (" / ".join(notes_parts) if notes_parts else "-")[:40],
            paid,
            apt.status or "-",
        ])
    if len(consult_data) > 1:
        elements.append(_build_table(
            consult_data,
            col_widths=[0.65 * inch, 0.55 * inch, 0.85 * inch, 0.7 * inch, 0.85 * inch, 0.95 * inch, 0.65 * inch, 0.55 * inch],
            wrap_body=True,
        ))
    else:
        elements.append(Paragraph("No appointments on record.", body_style))
    elements.append(Spacer(1, 14))

    records = (
        db.query(MedicalRecord)
        .filter(MedicalRecord.patient_id == profile.id, MedicalRecord.is_active == True)
        .order_by(MedicalRecord.created_at.desc())
        .limit(20)
        .all()
    )
    if records:
        elements.append(Paragraph("Diagnoses & Doctor Notes", subtitle_style))
        rec_data = [["Date", "Doctor", "Diagnosis", "Notes", "Severity"]]
        for r in records:
            rec_data.append([
                r.created_at.strftime("%Y-%m-%d") if r.created_at else "-",
                _doctor_display_name(db, r.doctor_id),
                (r.diagnosis or "-")[:35],
                (r.notes or "-")[:40],
                r.severity or "-",
            ])
        elements.append(_build_table(rec_data, col_widths=[0.75 * inch, 0.95 * inch, 1.35 * inch, 1.75 * inch, 0.65 * inch], wrap_body=True))
        elements.append(Spacer(1, 14))

    prescriptions = (
        db.query(Prescription)
        .join(MedicalRecord, Prescription.medical_record_id == MedicalRecord.id)
        .filter(MedicalRecord.patient_id == profile.id, Prescription.status == "active")
        .order_by(Prescription.created_at.desc())
        .all()
    )
    rx_rows = [["Medication", "Dosage", "Frequency", "Duration", "Notes"]]
    for rx in prescriptions:
        items = db.query(PrescriptionItem).filter(PrescriptionItem.prescription_id == rx.id).all()
        for item in items:
            rx_rows.append([
                item.medication_name or "-",
                item.dosage or "-",
                item.frequency or "-",
                item.duration or "-",
                (item.notes or "-")[:30],
            ])
    if len(rx_rows) > 1:
        elements.append(Paragraph("Prescriptions", subtitle_style))
        elements.append(_build_table(rx_rows, col_widths=[1.3 * inch, 0.9 * inch, 1 * inch, 0.9 * inch, 1.4 * inch]))
        elements.append(Spacer(1, 14))

    sensors = (
        db.query(SensorData)
        .filter(SensorData.patient_id == profile.id)
        .order_by(SensorData.timestamp.desc())
        .limit(20)
        .all()
    )

    latest_sensor = sensors[0] if sensors else None
    if latest_sensor:
        elements.append(Paragraph("Latest Vitals (from clinic sensor)", subtitle_style))
        vitals = [
            ["Metric", "Value"],
            ["Heart Rate", f"{latest_sensor.heart_rate} bpm"],
            ["Temperature", f"{latest_sensor.temperature}°C"],
            ["GSR", f"{latest_sensor.gsr or 0:.0f}"],
            ["ECG", f"{latest_sensor.ecg or 0:.0f}"],
            ["EMG", f"{latest_sensor.emg or 0:.0f}"],
            ["Recorded", latest_sensor.timestamp.strftime("%Y-%m-%d %H:%M") if latest_sensor.timestamp else "-"],
        ]
        elements.append(_build_table(vitals, col_widths=[2 * inch, 4 * inch]))
        elements.append(Spacer(1, 12))

    if sensors:
        elements.append(Paragraph("Sensor Reading History", subtitle_style))
        sensor_data = [["Date/Time", "HR (bpm)", "Temp (°C)", "GSR", "ECG", "EMG"]]
        for s in reversed(sensors[:15]):
            sensor_data.append([
                s.timestamp.strftime("%Y-%m-%d %H:%M") if s.timestamp else "-",
                str(s.heart_rate) if s.heart_rate else "-",
                f"{s.temperature:.1f}" if s.temperature else "-",
                f"{s.gsr:.0f}" if s.gsr else "-",
                f"{s.ecg:.0f}" if s.ecg else "-",
                f"{s.emg:.0f}" if s.emg else "-",
            ])
        elements.append(_build_table(
            sensor_data,
            col_widths=[1.2 * inch, 0.7 * inch, 0.7 * inch, 0.6 * inch, 0.6 * inch, 0.6 * inch],
        ))
        elements.append(Spacer(1, 14))

        ordered = list(reversed(sensors[:15]))
        label_for = lambda s: s.timestamp.strftime("%m/%d %H:%M") if s.timestamp else "-"

        def _points(field: str) -> list[tuple[str, float]]:
            out: list[tuple[str, float]] = []
            for s in ordered:
                val = getattr(s, field, None)
                if val is None:
                    continue
                fv = float(val)
                if fv <= 0:
                    continue
                out.append((label_for(s), fv))
            return out

        hr_points = _points("heart_rate")
        temp_points = _points("temperature")
        gsr_points = _points("gsr")
        ecg_points = _points("ecg")
        emg_points = _points("emg")

        elements.append(Paragraph("Sensor Charts", subtitle_style))
        elements.append(Paragraph(
            "Waveform charts: ECG, EMG, and GSR only. Heart rate and temperature are shown as numbers in the table above.",
            body_style,
        ))
        elements.append(Spacer(1, 6))

        chart_specs = [
            ("GSR Chart", "Galvanic skin response (stress/conductance).", gsr_points, "GSR", "#6A1B9A"),
            ("ECG Chart", "Electrocardiogram signal level from clinic sensor.", ecg_points, "ECG", "#C62828"),
            ("EMG Chart", "Electromyography signal level from clinic sensor.", emg_points, "EMG", "#00838F"),
        ]
        for title, desc, pts, ylab, col in chart_specs:
            if not pts:
                continue
            chart = _make_line_chart(title, desc, pts, ylab, col)
            elements.append(_ChartFlowable(chart, 460, 164))
            elements.append(Spacer(1, 8))

    doc.build(
        elements,
        onFirstPage=lambda c, d: _header_footer(c, d, clinic_name),
        onLaterPages=lambda c, d: _header_footer(c, d, clinic_name),
    )
    buf.seek(0)

    filename = f"patient_report_{profile.first_name}_{profile.last_name}.pdf"
    return _pdf_stream(buf, filename)


def _patient_report_tabular(profile, db: Session, fmt: str):
    appointments = (
        db.query(Appointment)
        .filter(Appointment.patient_id == profile.id)
        .order_by(Appointment.date.desc(), Appointment.time_slot.desc())
        .all()
    )
    consult_rows = [["Date", "Time", "Doctor", "Receptionist", "Diagnosis", "Notes", "Paid", "Status"]]
    for apt in appointments:
        payment = db.query(Payment).filter(Payment.appointment_id == apt.id).first()
        record = (
            db.query(MedicalRecord)
            .filter(MedicalRecord.appointment_id == apt.id, MedicalRecord.is_active == True)
            .first()
        )
        receptionist = (
            _profile_display_name(db, payment.receptionist_id)
            if payment and payment.receptionist_id
            else "-"
        )
        paid = "-"
        if payment:
            paid = f"{payment.amount} ({payment.payment_method or 'N/A'})"
        notes_parts = [n for n in [apt.notes, record.notes if record else None] if n]
        consult_rows.append([
            str(apt.date or "-"),
            format_time_12h(apt.time_slot),
            _doctor_display_name(db, apt.doctor_id),
            receptionist,
            (record.diagnosis if record else "-")[:80],
            (" / ".join(notes_parts) if notes_parts else "-")[:80],
            paid,
            apt.status or "-",
        ])

    diag_rows = [["Date", "Doctor", "Diagnosis", "Severity", "Notes"]]
    records = (
        db.query(MedicalRecord)
        .filter(MedicalRecord.patient_id == profile.id, MedicalRecord.is_active == True)
        .order_by(MedicalRecord.created_at.desc())
        .limit(50)
        .all()
    )
    for r in records:
        diag_rows.append([
            r.created_at.strftime("%Y-%m-%d") if r.created_at else "-",
            _doctor_display_name(db, r.doctor_id),
            (r.diagnosis or "-")[:80],
            r.severity or "-",
            (r.notes or "-")[:80],
        ])

    rx_rows = [["Medication", "Dosage", "Frequency", "Duration", "Notes"]]
    prescriptions = (
        db.query(Prescription)
        .join(MedicalRecord, Prescription.medical_record_id == MedicalRecord.id)
        .filter(MedicalRecord.patient_id == profile.id, Prescription.status == "active")
        .all()
    )
    for rx in prescriptions:
        items = db.query(PrescriptionItem).filter(PrescriptionItem.prescription_id == rx.id).all()
        for item in items:
            rx_rows.append([
                item.medication_name or "-",
                item.dosage or "-",
                item.frequency or "-",
                item.duration or "-",
                (item.notes or "-")[:40],
            ])

    sensor_rows = [["Date/Time", "HR", "Temp", "GSR", "ECG", "EMG"]]
    sensors = (
        db.query(SensorData)
        .filter(SensorData.patient_id == profile.id)
        .order_by(SensorData.timestamp.desc())
        .limit(30)
        .all()
    )
    for s in sensors:
        sensor_rows.append([
            s.timestamp.strftime("%Y-%m-%d %H:%M") if s.timestamp else "-",
            str(s.heart_rate),
            f"{s.temperature:.1f}" if s.temperature else "-",
            f"{s.gsr:.0f}" if s.gsr else "-",
            f"{s.ecg:.0f}" if s.ecg else "-",
            f"{s.emg:.0f}" if s.emg else "-",
        ])

    base = f"patient_report_{profile.first_name}_{profile.last_name}"
    if fmt == "csv":
        combined = consult_rows + [[""]] + diag_rows + [[""]] + rx_rows + [[""]] + sensor_rows
        return stream_csv(combined, f"{base}.csv")
    return stream_xlsx({
        "Consultations": consult_rows,
        "Diagnoses": diag_rows,
        "Prescriptions": rx_rows,
        "Vitals": sensor_rows,
    }, f"{base}.xlsx")


def _collect_clinic_audit_rows(db: Session, date_from: date | None, date_to: date | None):
    apt_query = db.query(Appointment)
    if date_from:
        apt_query = apt_query.filter(Appointment.date >= date_from)
    if date_to:
        apt_query = apt_query.filter(Appointment.date <= date_to)
    appointments = apt_query.order_by(Appointment.date.desc(), Appointment.time_slot.desc()).limit(300).all()

    apt_rows = [["Date", "Time", "Patient", "Doctor", "Status", "Queue", "Created"]]
    for apt in appointments:
        patient = db.query(Profile).filter(Profile.id == apt.patient_id).first()
        apt_rows.append([
            str(apt.date),
            format_time_12h(apt.time_slot),
            f"{patient.first_name} {patient.last_name}" if patient else "N/A",
            _doctor_display_name(db, apt.doctor_id),
            apt.status,
            str(apt.queue_number or "-"),
            apt.created_at.strftime("%Y-%m-%d %H:%M") if apt.created_at else "-",
        ])

    pay_query = db.query(Payment).join(Appointment, Appointment.id == Payment.appointment_id)
    if date_from:
        pay_query = pay_query.filter(Appointment.date >= date_from)
    if date_to:
        pay_query = pay_query.filter(Appointment.date <= date_to)
    payments = pay_query.order_by(Payment.created_at.desc()).limit(200).all()

    pay_rows = [[
        "Invoice", "Date", "Patient", "Amount", "Method", "Status",
        "Recorded By", "Recorded At", "Payment Proof", "Refund Proof",
    ]]
    for p in payments:
        apt = db.query(Appointment).filter(Appointment.id == p.appointment_id).first()
        patient = db.query(Profile).filter(Profile.id == apt.patient_id).first() if apt else None
        pay_rows.append([
            f"INV-{p.id[:8].upper()}",
            str(apt.date) if apt else "-",
            f"{patient.first_name} {patient.last_name}" if patient else "N/A",
            f"{p.amount:.0f} EGP",
            p.payment_method or "-",
            p.payment_status,
            _profile_display_name(db, p.receptionist_id) if p.receptionist_id else "-",
            p.created_at.strftime("%Y-%m-%d %H:%M") if p.created_at else "-",
            p.proof_url or "-",
            p.refund_proof_url or "-",
        ])

    refunds = [p for p in payments if p.payment_status == "refunded" or p.refunded_at]
    ref_rows = [[
        "Invoice", "Amount", "Refunded By", "Refunded At", "Reason", "Refund Proof",
    ]]
    for p in refunds:
        ref_rows.append([
            f"INV-{p.id[:8].upper()}",
            f"{p.amount:.0f} EGP",
            _profile_display_name(db, p.refunded_by) if p.refunded_by else "-",
            p.refunded_at.strftime("%Y-%m-%d %H:%M") if p.refunded_at else "-",
            p.refund_reason or "-",
            p.refund_proof_url or "-",
        ])

    log_query = db.query(AuditLog)
    if date_from:
        log_query = log_query.filter(AuditLog.timestamp >= datetime.combine(date_from, datetime.min.time()))
    if date_to:
        log_query = log_query.filter(AuditLog.timestamp <= datetime.combine(date_to, datetime.max.time()))
    logs = log_query.order_by(AuditLog.timestamp.desc()).limit(400).all()

    log_rows = [["Timestamp", "Staff / System", "Action", "Entity Type", "Entity ID", "Details"]]
    for log in logs:
        log_rows.append([
            log.timestamp.strftime("%Y-%m-%d %H:%M") if log.timestamp else "-",
            staff_display_name(db, log.user_id),
            log.action,
            log.entity_type or "-",
            (log.entity_id or "-")[:36],
            log.details or "-",
        ])

    return apt_rows, pay_rows, ref_rows, log_rows, payments


@router.get("/my-report")
def my_report(
    fmt: str = Query("pdf", alias="format"),
    user: User = Depends(_get_report_user),
    db: Session = Depends(get_db),
):
    _require_roles(user, "patient")
    profile = db.query(Profile).filter(Profile.user_id == user.id).first()
    if not profile:
        raise HTTPException(status_code=404, detail="Profile not found. Please complete your profile first.")
    export_fmt = _normalize_format(fmt)
    if export_fmt == "pdf":
        return _generate_patient_report(profile, db)
    return _patient_report_tabular(profile, db, export_fmt)


@router.get("/patient/{patient_id}")
def patient_report(
    patient_id: str,
    fmt: str = Query("pdf", alias="format"),
    user: User = Depends(_get_report_user),
    db: Session = Depends(get_db),
):
    _require_roles(user, "doctor", "admin", "receptionist")
    profile = db.query(Profile).filter(Profile.id == patient_id).first()
    if not profile:
        raise HTTPException(status_code=404, detail="Patient not found")
    export_fmt = _normalize_format(fmt)
    if export_fmt == "pdf":
        return _generate_patient_report(profile, db)
    return _patient_report_tabular(profile, db, export_fmt)


@router.get("/appointments")
def appointment_report(
    user: User = Depends(_get_report_user),
    date_from: date = Query(None),
    date_to: date = Query(None),
    fmt: str = Query("pdf", alias="format"),
    db: Session = Depends(get_db),
):
    _require_roles(user, "admin", "receptionist")
    export_fmt = _normalize_format(fmt)

    query = db.query(Appointment)
    if date_from:
        query = query.filter(Appointment.date >= date_from)
    if date_to:
        query = query.filter(Appointment.date <= date_to)
    appointments = query.order_by(Appointment.date.desc()).limit(200).all()

    table_data = [["Date", "Time", "Patient", "Doctor", "Status", "Queue", "Payment", "Paid By"]]
    for apt in appointments:
        patient = db.query(Profile).filter(Profile.id == apt.patient_id).first()
        doctor = db.query(Doctor).filter(Doctor.id == apt.doctor_id).first()
        doc_profile = db.query(Profile).filter(Profile.id == doctor.profile_id).first() if doctor else None
        payment = db.query(Payment).filter(Payment.appointment_id == apt.id).first()
        pay_str = "-"
        paid_by = "-"
        if payment:
            pay_str = f"{payment.amount} EGP ({payment.payment_status})"
            if payment.receptionist_id:
                paid_by = _profile_display_name(db, payment.receptionist_id)
        table_data.append([
            str(apt.date),
            format_time_12h(apt.time_slot),
            f"{patient.first_name} {patient.last_name}" if patient else "N/A",
            f"Dr. {doc_profile.last_name}" if doc_profile else "N/A",
            apt.status,
            str(apt.queue_number or "-"),
            pay_str,
            paid_by,
        ])

    if export_fmt == "csv":
        return stream_csv(table_data, "appointment_report.csv")
    if export_fmt == "xlsx":
        return stream_xlsx({"Appointments": table_data}, "appointment_report.xlsx")

    clinic_name = _get_clinic_name(db)
    styles = getSampleStyleSheet()
    title_style = ParagraphStyle("Title2", parent=styles["Title"], fontSize=16, spaceAfter=12)

    buf = io.BytesIO()
    doc = SimpleDocTemplate(buf, pagesize=A4, topMargin=70, bottomMargin=50)
    elements = []

    period = ""
    if date_from and date_to:
        period = f" ({date_from} to {date_to})"
    elements.append(Paragraph(f"Appointment Report{period}", title_style))
    elements.append(Spacer(1, 10))

    elements.append(_build_table(
        table_data,
        col_widths=[0.7 * inch, 0.6 * inch, 1.05 * inch, 0.85 * inch, 0.65 * inch, 0.45 * inch, 0.95 * inch, 0.85 * inch],
        wrap_body=True,
    ))

    doc.build(
        elements,
        onFirstPage=lambda c, d: _header_footer(c, d, clinic_name),
        onLaterPages=lambda c, d: _header_footer(c, d, clinic_name),
    )
    return _pdf_stream(buf, "appointment_report.pdf")


@router.get("/doctors")
def doctor_report(
    user: User = Depends(_get_report_user),
    fmt: str = Query("pdf", alias="format"),
    db: Session = Depends(get_db),
):
    _require_roles(user, "admin")
    export_fmt = _normalize_format(fmt)

    doctors = db.query(Doctor).all()
    table_data = [["Name", "Specialty", "Qualifications", "Appointments"]]
    for d in doctors:
        prof = db.query(Profile).filter(Profile.id == d.profile_id).first()
        from models import Specialty
        spec = db.query(Specialty).filter(Specialty.id == d.specialty_id).first()
        apt_count = db.query(Appointment).filter(Appointment.doctor_id == d.id).count()
        table_data.append([
            f"Dr. {prof.first_name} {prof.last_name}" if prof else "N/A",
            spec.name if spec else "N/A",
            d.qualifications or "N/A",
            str(apt_count),
        ])

    if export_fmt == "csv":
        return stream_csv(table_data, "doctor_report.csv")
    if export_fmt == "xlsx":
        return stream_xlsx({"Doctors": table_data}, "doctor_report.xlsx")

    clinic_name = _get_clinic_name(db)
    styles = getSampleStyleSheet()
    title_style = ParagraphStyle("Title2", parent=styles["Title"], fontSize=16, spaceAfter=12)

    buf = io.BytesIO()
    doc = SimpleDocTemplate(buf, pagesize=A4, topMargin=70, bottomMargin=50)
    elements = [
        Paragraph("Doctor Report", title_style),
        Spacer(1, 10),
        _build_table(
            table_data,
            col_widths=[1.8 * inch, 1.3 * inch, 2 * inch, 1 * inch],
            wrap_body=True,
        ),
    ]

    doc.build(
        elements,
        onFirstPage=lambda c, d: _header_footer(c, d, clinic_name),
        onLaterPages=lambda c, d: _header_footer(c, d, clinic_name),
    )
    return _pdf_stream(buf, "doctor_report.pdf")


def _log_relates_to_patient(db: Session, log: AuditLog, patient_id: str) -> bool:
    if log.entity_type == "medical_record":
        rec = db.query(MedicalRecord).filter(MedicalRecord.id == log.entity_id).first()
        return rec is not None and rec.patient_id == patient_id
    if log.entity_type == "prescription":
        rx = db.query(Prescription).filter(Prescription.id == log.entity_id).first()
        if not rx:
            return False
        rec = db.query(MedicalRecord).filter(MedicalRecord.id == rx.medical_record_id).first()
        return rec is not None and rec.patient_id == patient_id
    if log.entity_type == "appointment":
        apt = db.query(Appointment).filter(Appointment.id == log.entity_id).first()
        return apt is not None and apt.patient_id == patient_id
    return False


def _collect_doctor_activity_rows(
    db: Session,
    user_id: str,
    patient_id: str | None = None,
    date_from: date | None = None,
    date_to: date | None = None,
) -> list[list[str]]:
    query = db.query(AuditLog).filter(AuditLog.user_id == user_id)
    if date_from:
        query = query.filter(AuditLog.timestamp >= datetime.combine(date_from, datetime.min.time()))
    if date_to:
        query = query.filter(AuditLog.timestamp <= datetime.combine(date_to, datetime.max.time()))
    logs = query.order_by(AuditLog.timestamp.desc()).limit(500).all()

    rows = [["Timestamp", "Action", "Entity Type", "Entity ID", "Details"]]
    for log in logs:
        if patient_id and not _log_relates_to_patient(db, log, patient_id):
            continue
        rows.append([
            log.timestamp.strftime("%Y-%m-%d %H:%M") if log.timestamp else "-",
            log.action,
            log.entity_type or "-",
            (log.entity_id or "-")[:36],
            log.details or "-",
        ])
    return rows


@router.get("/doctor-activity")
def doctor_activity_report(
    patient_id: str | None = Query(None),
    date_from: date | None = Query(None),
    date_to: date | None = Query(None),
    fmt: str = Query("pdf", alias="format"),
    user: User = Depends(_get_report_user),
    db: Session = Depends(get_db),
):
    """Downloadable audit trail of all actions by the logged-in doctor."""
    _require_roles(user, "doctor")
    export_fmt = _normalize_format(fmt)

    profile = db.query(Profile).filter(Profile.user_id == user.id).first()
    doctor_name = "Doctor"
    if profile:
        doctor_name = f"Dr. {profile.first_name or ''} {profile.last_name or ''}".strip()

    patient_name = None
    if patient_id:
        p = db.query(Profile).filter(Profile.id == patient_id).first()
        if p:
            patient_name = f"{p.first_name or ''} {p.last_name or ''}".strip()

    table_data = _collect_doctor_activity_rows(db, user.id, patient_id, date_from, date_to)
    filename_stem = "doctor_activity_report"
    if patient_id:
        filename_stem = f"doctor_activity_{patient_id[:8]}"

    if export_fmt == "csv":
        return stream_csv(table_data, f"{filename_stem}.csv")
    if export_fmt == "xlsx":
        return stream_xlsx({"Doctor Activity": table_data}, f"{filename_stem}.xlsx")

    clinic_name = _get_clinic_name(db)
    styles = getSampleStyleSheet()
    title_style = ParagraphStyle("Title2", parent=styles["Title"], fontSize=16, spaceAfter=12)
    body_style = ParagraphStyle("Body2", parent=styles["Normal"], fontSize=10, spaceAfter=6)

    buf = io.BytesIO()
    doc = SimpleDocTemplate(buf, pagesize=landscape(A4), topMargin=70, bottomMargin=50)
    elements = [
        Paragraph("Doctor Activity Report", title_style),
        Paragraph(_escape_xml(f"Doctor: {doctor_name}"), body_style),
    ]
    if patient_name:
        elements.append(Paragraph(_escape_xml(f"Patient filter: {patient_name}"), body_style))
    if date_from or date_to:
        elements.append(Paragraph(
            _escape_xml(f"Period: {date_from or '…'} to {date_to or '…'}"),
            body_style,
        ))
    elements.append(Spacer(1, 10))
    elements.append(_build_table(
        table_data,
        col_widths=[1.2 * inch, 0.9 * inch, 1.0 * inch, 1.2 * inch, 3.2 * inch],
        wrap_body=True,
    ))

    doc.build(
        elements,
        onFirstPage=lambda c, d: _header_footer(c, d, clinic_name),
        onLaterPages=lambda c, d: _header_footer(c, d, clinic_name),
    )
    return _pdf_stream(buf, f"{filename_stem}.pdf")


@router.get("/clinic-audit")
def clinic_audit_report(
    user: User = Depends(_get_report_user),
    date_from: date = Query(None),
    date_to: date = Query(None),
    fmt: str = Query("pdf", alias="format"),
    db: Session = Depends(get_db),
):
    """Full traceability report: appointments, payments, refunds, staff activity log."""
    _require_roles(user, "admin", "receptionist")
    export_fmt = _normalize_format(fmt)

    apt_rows, pay_rows, ref_rows, log_rows, payments = _collect_clinic_audit_rows(db, date_from, date_to)

    payment_proof_entries = [
        {"label": _proof_label(p, db, kind="payment"), "path": _proof_file_path(p.proof_url), "url": p.proof_url or ""}
        for p in payments if p.proof_url
    ]
    refund_proof_entries = [
        {"label": _proof_label(p, db, kind="refund"), "path": _proof_file_path(p.refund_proof_url), "url": p.refund_proof_url or ""}
        for p in payments if p.refund_proof_url
    ]

    if export_fmt == "csv":
        combined = [["Section: Appointments"]] + apt_rows + [[""], ["Section: Payments"]] + pay_rows
        if len(ref_rows) > 1:
            combined += [[""], ["Section: Refunds"]] + ref_rows
        if payment_proof_entries:
            combined += [[""], ["Section: Payment Proof Files"], ["Reference", "File Path"]]
            combined += [[e["label"], e["url"]] for e in payment_proof_entries]
        if refund_proof_entries:
            combined += [[""], ["Section: Refund Proof Files"], ["Reference", "File Path"]]
            combined += [[e["label"], e["url"]] for e in refund_proof_entries]
        combined += [[""], ["Section: Staff Activity"]] + log_rows
        return stream_csv(combined, "clinic_audit_report.csv")
    if export_fmt == "xlsx":
        sheets: dict[str, list[list]] = {
            "Appointments": apt_rows,
            "Payments": pay_rows,
            "Staff Activity": log_rows,
        }
        if len(ref_rows) > 1:
            sheets["Refunds"] = ref_rows
        return stream_xlsx_with_proofs(
            sheets,
            payment_proof_entries,
            refund_proof_entries,
            "clinic_audit_report.xlsx",
        )

    clinic_name = _get_clinic_name(db)
    styles = getSampleStyleSheet()
    title_style = ParagraphStyle("Title2", parent=styles["Title"], fontSize=16, spaceAfter=12)
    subtitle_style = ParagraphStyle(
        "Sub", parent=styles["Heading3"], fontSize=11, spaceAfter=6, textColor=colors.HexColor("#2c3e50")
    )
    body_style = ParagraphStyle("BodySmall", parent=styles["Normal"], fontSize=8, spaceAfter=4)
    caption_style = ParagraphStyle(
        "ProofCaption",
        parent=styles["Normal"],
        fontSize=9,
        leading=11,
        spaceAfter=4,
        textColor=colors.HexColor("#2c3e50"),
        fontName="Helvetica-Bold",
    )

    period = ""
    if date_from and date_to:
        period = f" ({date_from} to {date_to})"
    elif date_from:
        period = f" (from {date_from})"
    elif date_to:
        period = f" (until {date_to})"

    page = landscape(A4)
    buf = io.BytesIO()
    doc = SimpleDocTemplate(buf, pagesize=page, topMargin=60, bottomMargin=45, leftMargin=36, rightMargin=36)
    elements = []

    elements.append(Paragraph(f"Clinic Audit & Activity Report{period}", title_style))
    elements.append(Paragraph(
        "Complete trace of appointments, payments, refunds, and receptionist/staff actions.",
        body_style,
    ))
    elements.append(Spacer(1, 10))

    elements.append(Paragraph("All Appointments", subtitle_style))
    elements.append(_build_table(
        apt_rows,
        col_widths=[0.85 * inch, 0.7 * inch, 1.15 * inch, 1.1 * inch, 0.75 * inch, 0.5 * inch, 1.0 * inch],
        wrap_body=True,
    ))
    elements.append(Spacer(1, 12))

    elements.append(Paragraph("Payments & Invoices", subtitle_style))
    elements.append(_build_table(
        pay_rows,
        col_widths=[
            0.75 * inch, 0.65 * inch, 0.95 * inch, 0.6 * inch, 0.55 * inch,
            0.55 * inch, 0.85 * inch, 0.85 * inch, 0.95 * inch, 0.95 * inch,
        ],
        wrap_body=True,
    ))
    elements.append(Spacer(1, 12))

    elements.append(Paragraph("Refunds", subtitle_style))
    if len(ref_rows) > 1:
        elements.append(_build_table(
            ref_rows,
            col_widths=[0.85 * inch, 0.7 * inch, 1.0 * inch, 0.95 * inch, 1.6 * inch, 1.0 * inch],
            wrap_body=True,
        ))
    else:
        elements.append(Paragraph("No refunds in this period.", body_style))
    elements.append(Spacer(1, 12))

    elements.append(Paragraph("Staff Activity Log (Audit Trail)", subtitle_style))
    elements.append(Paragraph(
        "Every confirm, cancel, queue change, payment, refund, reschedule, and automatic no-show is logged here.",
        body_style,
    ))
    elements.append(Spacer(1, 6))
    if len(log_rows) > 1:
        elements.append(_build_table(
            log_rows,
            col_widths=[1.05 * inch, 1.2 * inch, 0.95 * inch, 0.85 * inch, 1.05 * inch, 3.5 * inch],
            wrap_body=True,
        ))
    else:
        elements.append(Paragraph("No activity logs in this period.", body_style))

    image_max_width = page[0] - doc.leftMargin - doc.rightMargin - 0.2 * inch
    image_max_height = page[1] - doc.topMargin - doc.bottomMargin - 1.2 * inch
    _append_payment_proof_gallery(
        elements, payments, db, subtitle_style, caption_style, body_style, image_max_width, image_max_height,
    )
    _append_refund_proof_gallery(
        elements, payments, db, subtitle_style, caption_style, body_style, image_max_width, image_max_height,
    )

    doc.build(
        elements,
        onFirstPage=lambda c, d: _header_footer(c, d, clinic_name),
        onLaterPages=lambda c, d: _header_footer(c, d, clinic_name),
    )
    return _pdf_stream(buf, "clinic_audit_report.pdf")

import logging
import os
import smtplib
import ssl
import threading
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText

import httpx
from sqlalchemy.orm import Session

from models import ClinicSettings

logger = logging.getLogger(__name__)


def get_sender_info(db: Session) -> tuple[str, str]:
    settings = db.query(ClinicSettings).first()
    clinic_name = settings.clinic_name if settings else "Octocare Clinic"
    default_sender = os.getenv("EMAIL_FROM", os.getenv("SMTP_USER", "clinova.clinic@gmail.com")).strip().lower()
    sender = (
        settings.email.strip().lower()
        if settings and settings.email
        else default_sender
    )
    if sender != default_sender:
        logger.warning("Clinic sender %s overridden with verified sender %s", sender, default_sender)
        sender = default_sender
    return sender, clinic_name


def _smtp_config() -> dict:
    smtp_user = os.getenv("SMTP_USER", os.getenv("EMAIL_FROM", "clinova.clinic@gmail.com")).strip().lower()
    return {
        "host": os.getenv("SMTP_HOST", "").strip(),
        "port": int(os.getenv("SMTP_PORT", "587")),
        "user": smtp_user,
        "password": os.getenv("SMTP_PASSWORD", "").strip(),
        "use_tls": os.getenv("SMTP_USE_TLS", "true").lower() == "true",
    }


def email_provider_status() -> dict:
    cfg = _smtp_config()
    brevo = bool(os.getenv("BREVO_API_KEY", "").strip())
    resend = bool(os.getenv("RESEND_API_KEY", "").strip())
    smtp = bool(cfg["host"] and cfg["password"])
    if brevo:
        provider = "brevo"
    elif resend:
        provider = "resend"
    elif smtp:
        provider = "smtp"
    else:
        provider = "none"
    return {
        "provider": provider,
        "configured": provider != "none",
        "brevo": brevo,
        "resend": resend,
        "smtp": smtp,
        "from_email": os.getenv("EMAIL_FROM", cfg["user"] or "clinova.clinic@gmail.com"),
    }


def smtp_is_configured() -> bool:
    return email_provider_status()["configured"]


def _otp_message(clinic_name: str, otp_code: str, purpose: str) -> tuple[str, str, str]:
    if purpose == "signup":
        subject = f"{clinic_name} verification code"
        body = (
            f"Welcome to {clinic_name}!\n\n"
            f"Your verification code is: {otp_code}\n\n"
            "Enter this code in the app to confirm your email address.\n"
            "This code expires in 10 minutes.\n\n"
            "If you do not see this email, check your Spam or Junk folder.\n\n"
            "If you did not create an account, ignore this email."
        )
        html_body = (
            f"<p>Welcome to <strong>{clinic_name}</strong>!</p>"
            f"<p>Your verification code is:</p>"
            f"<p style='font-size:28px;font-weight:bold;letter-spacing:4px'>{otp_code}</p>"
            "<p>Enter this code in the app to confirm your email address.<br>"
            "This code expires in 10 minutes.</p>"
            "<p>If you do not see this email, check your <strong>Spam or Junk</strong> folder.</p>"
        )
    else:
        subject = f"{clinic_name} password reset code"
        body = (
            f"You requested a password reset for {clinic_name}.\n\n"
            f"Your reset code is: {otp_code}\n\n"
            "Enter this code in the app to set a new password.\n"
            "This code expires in 10 minutes.\n\n"
            "If you do not see this email, check your Spam or Junk folder.\n\n"
            "If you did not request this, ignore this email."
        )
        html_body = (
            f"<p>You requested a password reset for <strong>{clinic_name}</strong>.</p>"
            f"<p>Your reset code is:</p>"
            f"<p style='font-size:28px;font-weight:bold;letter-spacing:4px'>{otp_code}</p>"
            "<p>Enter this code in the app to set a new password.<br>"
            "This code expires in 10 minutes.</p>"
            "<p>If you do not see this email, check your <strong>Spam or Junk</strong> folder.</p>"
        )
    return subject, body, html_body


def _send_via_brevo(from_addr: str, from_name: str, to_email: str, subject: str, body: str, html_body: str | None) -> None:
    api_key = os.getenv("BREVO_API_KEY", "").strip()
    if not api_key:
        raise RuntimeError("BREVO_API_KEY is not set")

    payload = {
        "sender": {"name": from_name, "email": from_addr},
        "to": [{"email": to_email}],
        "subject": subject,
        "textContent": body,
    }
    if html_body:
        payload["htmlContent"] = html_body

    response = httpx.post(
        "https://api.brevo.com/v3/smtp/email",
        headers={"api-key": api_key, "content-type": "application/json"},
        json=payload,
        timeout=20.0,
    )
    if response.status_code >= 400:
        detail = response.text[:500]
        detail_lower = detail.lower()
        if "not verified" in detail_lower or "sender" in detail_lower:
            raise RuntimeError(
                f"Brevo rejected sender {from_addr}. Verify this email in Brevo → Senders. Details: {detail}"
            )
        if response.status_code == 401 and (
            "ip" in detail_lower
            or "authorised" in detail_lower
            or "authorized" in detail_lower
            or "unrecognised" in detail_lower
            or "unrecognized" in detail_lower
        ):
            raise RuntimeError(
                "Brevo blocked this server's IP address. Railway IPs change on redeploy — "
                "in Brevo go to Security → Authorized IPs and disable IP restriction (recommended), "
                "or re-add the current Railway outbound IP after each deploy. "
                f"Details: {detail}"
            )
        raise RuntimeError(f"Brevo API error {response.status_code}: {detail}")
    print(f"[Octocare Clinic Email] Brevo accepted message to {to_email}: {response.text[:200]}", flush=True)


def _send_via_resend(from_addr: str, from_name: str, to_email: str, subject: str, body: str, html_body: str | None) -> None:
    api_key = os.getenv("RESEND_API_KEY", "").strip()
    if not api_key:
        raise RuntimeError("RESEND_API_KEY is not set")

    payload = {
        "from": f"{from_name} <{from_addr}>",
        "to": [to_email],
        "subject": subject,
        "text": body,
    }
    if html_body:
        payload["html"] = html_body

    response = httpx.post(
        "https://api.resend.com/emails",
        headers={"Authorization": f"Bearer {api_key}", "content-type": "application/json"},
        json=payload,
        timeout=20.0,
    )
    if response.status_code >= 400:
        raise RuntimeError(f"Resend API error {response.status_code}: {response.text[:300]}")


def _send_via_smtp(from_addr: str, to_email: str, msg: MIMEMultipart) -> None:
    cfg = _smtp_config()
    if not cfg["host"] or not cfg["password"]:
        raise RuntimeError(
            "Email is not configured. Set BREVO_API_KEY (recommended on Railway) or SMTP settings."
        )

    from_addr = from_addr.strip().lower()
    to_email = to_email.strip().lower()
    envelope_from = cfg["user"]

    errors: list[str] = []
    attempts = []
    if cfg["port"] == 465:
        attempts.append((cfg["host"], 465, False, True))
    else:
        if cfg["use_tls"]:
            attempts.append((cfg["host"], cfg["port"], True, False))
        attempts.append((cfg["host"], 465, False, True))
        if not cfg["use_tls"]:
            attempts.append((cfg["host"], cfg["port"], False, False))

    seen: set[tuple] = set()
    ordered_attempts = []
    for item in attempts:
        if item not in seen:
            seen.add(item)
            ordered_attempts.append(item)

    for host, port, use_tls, use_ssl in ordered_attempts:
        try:
            if use_ssl:
                context = ssl.create_default_context()
                with smtplib.SMTP_SSL(host, port, timeout=20, context=context) as server:
                    server.login(cfg["user"], cfg["password"])
                    server.sendmail(envelope_from, [to_email], msg.as_string())
            else:
                with smtplib.SMTP(host, port, timeout=20) as server:
                    server.ehlo()
                    if use_tls:
                        server.starttls(context=ssl.create_default_context())
                        server.ehlo()
                    server.login(cfg["user"], cfg["password"])
                    server.sendmail(envelope_from, [to_email], msg.as_string())
            logger.info("Email sent to %s via SMTP %s:%s", to_email, host, port)
            return
        except Exception as exc:
            errors.append(f"{host}:{port} -> {exc}")
            logger.warning("SMTP attempt failed (%s:%s): %s", host, port, exc)

    raise RuntimeError("Could not send email via SMTP. " + " | ".join(errors))


def _dispatch_email(from_addr: str, from_name: str, to_email: str, subject: str, body: str, html_body: str | None) -> str:
    status = email_provider_status()
    if status["brevo"]:
        _send_via_brevo(from_addr, from_name, to_email, subject, body, html_body)
        return "brevo"
    if status["resend"]:
        _send_via_resend(from_addr, from_name, to_email, subject, body, html_body)
        return "resend"

    msg = MIMEMultipart("alternative")
    msg["From"] = f"{from_name} <{from_addr}>"
    msg["To"] = to_email
    msg["Subject"] = subject
    msg["Reply-To"] = from_addr
    msg.attach(MIMEText(body, "plain", "utf-8"))
    if html_body:
        msg.attach(MIMEText(html_body, "html", "utf-8"))
    _send_via_smtp(from_addr, to_email, msg)
    return "smtp"


def send_email(db: Session, to_email: str, subject: str, body: str, html_body: str | None = None) -> bool:
    sender, clinic_name = get_sender_info(db)
    to_email = to_email.lower().strip()

    try:
        provider = _dispatch_email(sender, clinic_name, to_email, subject, body, html_body)
        logger.info("Email sent to %s via %s", to_email, provider)
        print(f"[Octocare Clinic Email] Sent to {to_email} via {provider}", flush=True)
        return True
    except Exception as exc:
        logger.exception("Failed to send email to %s", to_email)
        print(
            f"\n[Octocare Clinic Email ERROR] {exc}\n"
            f"Provider status: {email_provider_status()}\n"
            f"To: {to_email}\nSubject: {subject}\n{body}\n",
            flush=True,
        )
        raise RuntimeError(str(exc)) from exc


def send_email_async(to_email: str, subject: str, body: str, html_body: str | None = None) -> None:
    def _task() -> None:
        from database import SessionLocal

        db = SessionLocal()
        try:
            send_email(db, to_email, subject, body, html_body=html_body)
        except Exception as exc:
            print(f"[Octocare Clinic Email] Background send failed to {to_email}: {exc}", flush=True)
        finally:
            db.close()

    thread = threading.Thread(target=_task, name=f"email-{to_email}", daemon=False)
    thread.start()


def send_otp_email(db: Session, to_email: str, otp_code: str, purpose: str) -> bool:
    _, clinic_name = get_sender_info(db)
    subject, body, html_body = _otp_message(clinic_name, otp_code, purpose)
    return send_email(db, to_email, subject, body, html_body=html_body)


def send_otp_email_async(to_email: str, otp_code: str, purpose: str) -> None:
    from database import SessionLocal

    db = SessionLocal()
    try:
        _, clinic_name = get_sender_info(db)
    finally:
        db.close()

    subject, body, html_body = _otp_message(clinic_name, otp_code, purpose)
    send_email_async(to_email, subject, body, html_body)


def send_patient_welcome_email(
    db: Session, to_email: str, temp_password: str, first_name: str = ""
) -> bool:
    _, clinic_name = get_sender_info(db)
    greeting = f"Hello {first_name}," if first_name else "Hello,"
    subject = f"{clinic_name} — Your patient account"
    body = (
        f"{greeting}\n\n"
        f"Your account at {clinic_name} has been created by our reception desk.\n\n"
        f"Temporary password: {temp_password}\n\n"
        "Steps to access your account:\n"
        "1. Open the Octocare Clinic app and sign in with your email and the temporary password above.\n"
        "2. Enter the 6-digit verification code sent to this email.\n"
        "3. Set a new personal password — only you will know it.\n\n"
        "For your safety, change your password before viewing your medical records.\n"
        "Never share your password with clinic staff.\n"
    )
    html_body = (
        f"<p>{greeting}</p>"
        f"<p>Your account at <strong>{clinic_name}</strong> has been created by our reception desk.</p>"
        f"<p>Temporary password: <strong>{temp_password}</strong></p>"
        "<p><strong>Steps to access your account:</strong></p>"
        "<ol>"
        "<li>Open the Octocare Clinic app and sign in with your email and temporary password.</li>"
        "<li>Enter the 6-digit verification code sent to this email.</li>"
        "<li>Set a new personal password — only you will know it.</li>"
        "</ol>"
        "<p>For your safety, change your password before viewing your medical records.</p>"
    )
    return send_email(db, to_email, subject, body, html_body=html_body)


def send_password_changed_email(db: Session, to_email: str) -> bool:
    _, clinic_name = get_sender_info(db)
    subject = f"{clinic_name} — Password changed"
    body = (
        f"Your {clinic_name} account password was changed successfully.\n\n"
        f"If you did not make this change, contact the clinic immediately at clinova.clinic@gmail.com.\n\n"
        "For your security, never share your password with anyone."
    )
    html_body = (
        f"<p>Your <strong>{clinic_name}</strong> account password was changed successfully.</p>"
        "<p>If you did not make this change, contact the clinic immediately.</p>"
        "<p>For your security, never share your password with anyone.</p>"
    )
    return send_email(db, to_email, subject, body, html_body=html_body)

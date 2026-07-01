import logging
import os
import smtplib
import ssl
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText

from sqlalchemy.orm import Session

from models import ClinicSettings

logger = logging.getLogger(__name__)


def get_sender_info(db: Session) -> tuple[str, str]:
    settings = db.query(ClinicSettings).first()
    clinic_name = settings.clinic_name if settings else "Smart Clinic"
    sender = (
        settings.email
        if settings and settings.email
        else os.getenv("SMTP_USER", "clinova.clinic@gmail.com")
    )
    return sender.strip().lower(), clinic_name


def _smtp_config() -> dict:
    smtp_user = os.getenv("SMTP_USER", "clinova.clinic@gmail.com").strip().lower()
    return {
        "host": os.getenv("SMTP_HOST", "").strip(),
        "port": int(os.getenv("SMTP_PORT", "587")),
        "user": smtp_user,
        "password": os.getenv("SMTP_PASSWORD", "").strip(),
        "use_tls": os.getenv("SMTP_USE_TLS", "true").lower() == "true",
    }


def smtp_is_configured() -> bool:
    cfg = _smtp_config()
    return bool(cfg["host"] and cfg["password"])


def _send_via_smtp(from_addr: str, to_email: str, msg: MIMEMultipart) -> None:
    cfg = _smtp_config()
    if not cfg["host"] or not cfg["password"]:
        raise RuntimeError(
            "Email is not configured on the server. Add SMTP settings to backend/.env and restart the backend."
        )

    from_addr = from_addr.strip().lower()
    to_email = to_email.strip().lower()
    envelope_from = cfg["user"]

    errors: list[str] = []

    # Try STARTTLS on port 587 first, then SSL on 465.
    attempts = [(cfg["host"], cfg["port"], cfg["use_tls"], False)]
    if cfg["port"] != 465:
        attempts.append((cfg["host"], 465, False, True))

    for host, port, use_tls, use_ssl in attempts:
        try:
            if use_ssl:
                context = ssl.create_default_context()
                with smtplib.SMTP_SSL(host, port, timeout=15, context=context) as server:
                    server.login(cfg["user"], cfg["password"])
                    server.sendmail(envelope_from, [to_email], msg.as_string())
            else:
                with smtplib.SMTP(host, port, timeout=15) as server:
                    server.ehlo()
                    if use_tls:
                        server.starttls(context=ssl.create_default_context())
                        server.ehlo()
                    server.login(cfg["user"], cfg["password"])
                    server.sendmail(envelope_from, [to_email], msg.as_string())
            logger.info("Email sent to %s via %s:%s", to_email, host, port)
            return
        except Exception as exc:
            errors.append(f"{host}:{port} -> {exc}")
            logger.warning("SMTP attempt failed (%s:%s): %s", host, port, exc)

    raise RuntimeError("Could not send email. " + " | ".join(errors))


def send_email(db: Session, to_email: str, subject: str, body: str, html_body: str | None = None) -> bool:
    sender, clinic_name = get_sender_info(db)
    to_email = to_email.lower().strip()

    msg = MIMEMultipart("alternative")
    msg["From"] = f"{clinic_name} <{sender}>"
    msg["To"] = to_email
    msg["Subject"] = subject
    msg["Reply-To"] = sender
    msg.attach(MIMEText(body, "plain", "utf-8"))
    if html_body:
        msg.attach(MIMEText(html_body, "html", "utf-8"))

    try:
        _send_via_smtp(sender, to_email, msg)
        return True
    except Exception as exc:
        logger.exception("Failed to send email to %s", to_email)
        print(f"\n[Smart Clinic Email ERROR] {exc}\nTo: {to_email}\nSubject: {subject}\n{body}\n")
        raise RuntimeError(str(exc)) from exc


def send_otp_email(db: Session, to_email: str, otp_code: str, purpose: str) -> bool:
    _, clinic_name = get_sender_info(db)
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
    return send_email(db, to_email, subject, body, html_body=html_body)


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
        "1. Open the Smart Clinic app and sign in with your email and the temporary password above.\n"
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
        "<li>Open the Smart Clinic app and sign in with your email and temporary password.</li>"
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

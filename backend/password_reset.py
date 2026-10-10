"""One-time email codes for resetting a forgotten password.

Email goes out over SMTP. Set SMTP_HOST, SMTP_PORT, SMTP_USERNAME,
SMTP_PASSWORD and SMTP_FROM on the server (for Gmail: smtp.gmail.com, 587,
and an app password).
"""

import os
import secrets
import smtplib
import ssl
from datetime import datetime, timedelta
from email.message import EmailMessage

from sqlalchemy import text
from sqlalchemy.orm import Session

from auth import hash_password, verify_password
from database import PRIVATE_TEXT_COLUMNS
from models import User

CODE_TTL = timedelta(minutes=15)
RESEND_AFTER = timedelta(seconds=60)
MAX_ATTEMPTS = 5
SMTP_TIMEOUT_SECONDS = 20


class EmailNotConfigured(Exception):
    pass


class EmailSendFailed(Exception):
    pass


def issue_code(user: User, now: datetime) -> str | None:
    """Store a new code on the user. None while the last one is too fresh."""
    sent_at = user.reset_code_sent_at
    if sent_at is not None and now - sent_at < RESEND_AFTER:
        return None
    code = f"{secrets.randbelow(1_000_000):06d}"
    user.reset_code_hash = hash_password(code)
    user.reset_code_expires_at = now + CODE_TTL
    user.reset_code_sent_at = now
    user.reset_attempts = 0
    return code


def check_code(user: User, code: str, now: datetime) -> bool:
    """Count the attempt and say whether the code is valid and unexpired."""
    if user.reset_code_hash is None or user.reset_code_expires_at is None:
        return False
    if now > user.reset_code_expires_at or user.reset_attempts >= MAX_ATTEMPTS:
        return False
    user.reset_attempts += 1
    return verify_password(code, user.reset_code_hash)


def clear_code(user: User) -> None:
    user.reset_code_hash = None
    user.reset_code_expires_at = None
    user.reset_attempts = 0


def drop_sealed_text(db: Session, user_id: int) -> None:
    """After a reset the old data key is gone; its ciphertext is unreadable."""
    for table, columns in PRIVATE_TEXT_COLUMNS.items():
        for column in columns:
            db.execute(
                text(
                    f"UPDATE {table} SET {column} = '' "
                    f"WHERE user_id = :user_id AND {column} LIKE 'enc1:%'"
                ),
                {"user_id": user_id},
            )
    db.execute(
        text(
            "UPDATE notifications SET event_metadata = '{}'::jsonb "
            "WHERE user_id = :user_id AND event_metadata::text LIKE '%enc1:%'"
        ),
        {"user_id": user_id},
    )


def email_configured() -> bool:
    return all(
        os.getenv(name)
        for name in ("SMTP_HOST", "SMTP_USERNAME", "SMTP_PASSWORD", "SMTP_FROM")
    )


def send_code(to_address: str, code: str) -> None:
    if not email_configured():
        raise EmailNotConfigured()

    message = EmailMessage()
    message["Subject"] = "رمز إعادة تعيين كلمة المرور - وفّر"
    message["From"] = os.environ["SMTP_FROM"]
    message["To"] = to_address
    message.set_content(
        f"رمز إعادة تعيين كلمة المرور: {code}\n\n"
        "الرمز صالح لمدة 15 دقيقة.\n"
        "إذا لم تطلب إعادة التعيين، تجاهل هذه الرسالة."
    )

    port = int(os.getenv("SMTP_PORT") or "587")
    # smtplib does not check the certificate unless given a context.
    context = ssl.create_default_context()
    try:
        if port == 465:
            server = smtplib.SMTP_SSL(
                os.environ["SMTP_HOST"],
                port,
                timeout=SMTP_TIMEOUT_SECONDS,
                context=context,
            )
        else:
            server = smtplib.SMTP(
                os.environ["SMTP_HOST"], port, timeout=SMTP_TIMEOUT_SECONDS
            )
            server.starttls(context=context)
        with server:
            server.login(os.environ["SMTP_USERNAME"], os.environ["SMTP_PASSWORD"])
            server.send_message(message)
    except (OSError, smtplib.SMTPException) as error:
        raise EmailSendFailed() from error


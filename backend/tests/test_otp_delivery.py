"""OTP email delivery must report failures to callers."""
import os
import sys
import uuid
from pathlib import Path
from unittest.mock import patch

import pytest

BACKEND = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(BACKEND))

os.environ.setdefault("DATABASE_URL", "sqlite:///:memory:")

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from database import Base
from otp_service import _deliver_otp_email


@pytest.fixture()
def db_session():
    engine = create_engine("sqlite:///:memory:", connect_args={"check_same_thread": False})
    Base.metadata.create_all(bind=engine)
    Session = sessionmaker(bind=engine)
    session = Session()
    yield session
    session.close()


@patch("otp_service.send_otp_email", return_value=True)
def test_deliver_otp_email_success(mock_send, db_session):
    assert _deliver_otp_email(db_session, "pat@example.com", "123456", "signup") is True
    mock_send.assert_called_once()


@patch("otp_service.send_otp_email", side_effect=RuntimeError("smtp down"))
def test_deliver_otp_email_failure_returns_false(mock_send, db_session):
    assert _deliver_otp_email(db_session, "pat@example.com", "123456", "signup") is False

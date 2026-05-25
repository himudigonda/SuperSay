"""Tests for app.core.logging (S1-G6)."""

from __future__ import annotations

import json
import logging

import pytest

from app.core import logging as supersay_logging


@pytest.fixture(autouse=True)
def _reset_logging():
    # Make tests independent — reset the singleton-ish state.
    supersay_logging._configured = False  # type: ignore[attr-defined]
    root = logging.getLogger()
    root.handlers.clear()
    supersay_logging.set_correlation_id("test-cid")
    yield
    supersay_logging._configured = False  # type: ignore[attr-defined]


def test_logger_emits_valid_json(capsys):
    log = supersay_logging.get_logger("test_logger")
    log.info("evt.name", extra={"voice": "af_bella", "chars": 42})
    out = capsys.readouterr().out.strip()
    obj = json.loads(out)
    assert obj["level"] == "INFO"
    assert obj["logger"] == "test_logger"
    assert obj["msg"] == "evt.name"
    assert obj["cid"] == "test-cid"
    assert obj["voice"] == "af_bella"
    assert obj["chars"] == 42
    assert "ts" in obj


def test_logger_skips_non_serializable_extras_gracefully(capsys):
    log = supersay_logging.get_logger("test_logger")

    class Weird:
        def __repr__(self) -> str:
            return "<weird>"

    log.info("oddball", extra={"thing": Weird()})
    out = capsys.readouterr().out.strip()
    obj = json.loads(out)
    assert obj["thing"] == "<weird>"


def test_correlation_id_default_when_unset():
    supersay_logging._correlation_id.set("-")  # reset
    assert supersay_logging.current_correlation_id() == "-"


def test_set_correlation_id_round_trip():
    cid = supersay_logging.set_correlation_id("abc-123")
    assert cid == "abc-123"
    assert supersay_logging.current_correlation_id() == "abc-123"


def test_set_correlation_id_generates_when_none():
    cid = supersay_logging.set_correlation_id(None)
    assert isinstance(cid, str) and len(cid) >= 8


def test_configure_is_idempotent(capsys):
    supersay_logging.configure()
    supersay_logging.configure()
    supersay_logging.configure()
    root = logging.getLogger()
    # Three calls but only one handler should be installed.
    assert len(root.handlers) == 1

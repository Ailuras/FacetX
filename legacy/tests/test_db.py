"""Tests for the SQLite data layer and the fixes applied to it."""

from __future__ import annotations

import time

import pytest

from docsbot.db import ProjectDB


# ── create() / _migrate() ───────────────────────────────────────────────────

def test_create_fresh_db_succeeds(tmp_path):
    """_migrate() must not crash when run before the base schema exists."""
    db = ProjectDB.create(tmp_path / "fresh.sqlite")
    # The base tables exist and default buckets were seeded.
    assert db.list_buckets()
    assert db.list_tasks() == []
    db.close()


def test_open_old_db_gets_weeks_and_features(tmp_path):
    """Opening a DB without the later tables should add them via _migrate."""
    path = tmp_path / "old.sqlite"
    db = ProjectDB.create(path)
    db._conn.executescript("DROP TABLE weeks; DROP TABLE features;")
    db._conn.commit()
    db.close()

    reopened = ProjectDB.open(path)
    assert reopened is not None
    # These would raise OperationalError if the tables were missing.
    assert reopened.list_weeks() == []
    assert reopened.list_features() == []
    reopened.close()


# ── SQL-injection whitelist ─────────────────────────────────────────────────

def test_update_task_ignores_unknown_fields(db):
    t = db.create_task(title="orig")
    updated = db.update_task(t["id"], title="new", status="done")
    assert updated["title"] == "new"
    assert updated["status"] == "done"


def test_update_task_rejects_malicious_field_name(db):
    t = db.create_task(title="safe")
    malicious = 'title = (SELECT 1); DROP TABLE tasks; --'
    result = db.update_task(t["id"], **{malicious: "evil", "title": "kept"})
    # Legit field still applied; malicious key silently dropped.
    assert result["title"] == "kept"
    # Table survived — a query still works.
    assert db.get_task(t["id"]) is not None


def test_update_research_whitelist(db):
    r = db.create_research(title="r")
    result = db.update_research(r["id"], title="r2", **{"bad col": "x"})
    assert result["title"] == "r2"
    assert db.get_research(r["id"]) is not None


def test_update_feature_whitelist(db):
    f = db.create_feature(title="f")
    result = db.update_feature(f["id"], title="f2", **{"evil; DROP": "x"})
    assert result["title"] == "f2"


def test_upsert_week_whitelist(db):
    week = db.upsert_week("2026-W22", goal_title="Goal", **{"bad col": "x"})
    assert week["goal_title"] == "Goal"
    assert week["week_id"] == "2026-W22"


# ── updated_at precision ────────────────────────────────────────────────────

def test_updated_at_has_time_precision_and_changes(db):
    t = db.create_task(title="x")
    first = db.update_task(t["id"], title="a")["updated_at"]
    time.sleep(1)
    second = db.update_task(t["id"], title="b")["updated_at"]
    assert "T" in first  # ISO timestamp, not date-only
    assert first != second


# ── ID generation ───────────────────────────────────────────────────────────

def test_next_task_id_is_per_bucket(db):
    db.create_task(title="a", bucket="T")
    db.create_task(title="b", bucket="T")
    db.create_task(title="c", bucket="P0")
    assert db.next_task_id("T") == "T-03"
    assert db.next_task_id("P0") == "P0-02"
    assert db.next_task_id("P1") == "P1-01"


def test_next_task_id_handles_overflow_past_padding(db):
    db.create_task(title="big", bucket="T", task_id="T-99")
    assert db.next_task_id("T") == "T-100"


def test_next_research_and_feature_ids(db):
    db.create_research(title="r1")
    db.create_research(title="r2")
    assert db.next_research_id() == "R3"
    db.create_feature(title="f1")
    assert db.next_feature_id() == "F02"


# ── JSON round-trip / deserialization ───────────────────────────────────────

def test_task_json_fields_round_trip(db):
    t = db.create_task(title="x", tags=["a", "b"], serves=["T-01"])
    got = db.get_task(t["id"])
    assert got["tags"] == ["a", "b"]
    assert got["serves"] == ["T-01"]


def test_delete_returns_false_for_missing(db):
    assert db.delete_task("nope") is False
    assert db.update_task("nope", title="x") is None

"""Shared pytest fixtures for DocsBot tests.

Every test runs against a throwaway ~/.docsbot pointed at a tmp dir via the
DOCSBOT_DATA_DIR env var, so nothing touches the real user data directory.
"""

from __future__ import annotations

import importlib

import pytest

from docsbot.db import ProjectDB


@pytest.fixture(autouse=True)
def isolated_data_dir(tmp_path, monkeypatch):
    """Point DocsBot at a fresh tmp data dir for the duration of each test."""
    monkeypatch.setenv("DOCSBOT_DATA_DIR", str(tmp_path / "docsbot"))
    # config caches nothing, but reimport defensively in case of state.
    import docsbot.config as config
    importlib.reload(config)
    yield tmp_path


@pytest.fixture
def db(tmp_path) -> ProjectDB:
    """A fresh, empty project database."""
    database = ProjectDB.create(tmp_path / "db.sqlite")
    yield database
    database.close()

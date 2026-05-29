"""Tests for the project registry and slug handling."""

from __future__ import annotations

import pytest

from docsbot import config


def test_slugify():
    assert config._slugify("My Project") == "my-project"
    assert config._slugify("Hello World 123") == "hello-world-123"
    assert config._slugify("a/b\\c!@#") == "abc"


def test_create_and_list_project():
    created = config.create_project(name="Test Proj", tagline="hi")
    assert created["id"] == "test-proj"
    projects = config.list_projects()
    assert len(projects) == 1
    assert projects[0]["name"] == "Test Proj"
    assert projects[0]["tagline"] == "hi"


def test_create_duplicate_project_raises():
    config.create_project(name="Dup")
    with pytest.raises(ValueError, match="already exists"):
        config.create_project(name="Dup")


def test_create_invalid_name_raises():
    with pytest.raises(ValueError, match="Invalid project name"):
        config.create_project(name="!!!")


def test_project_base_none_for_missing():
    assert config.project_base("does-not-exist") is None


def test_list_projects_empty_when_no_dir():
    assert config.list_projects() == []

"""Tests for note creation and the plain-text → HTML conversion."""

from __future__ import annotations

from docsbot.db import _text_to_html


def test_text_to_html_wraps_paragraphs():
    out = _text_to_html("first para\n\nsecond para")
    assert "<p>first para</p>" in out
    assert "<p>second para</p>" in out


def test_text_to_html_applies_inline_markdown():
    out = _text_to_html("this is **bold** and `code`")
    assert "<strong>bold</strong>" in out
    assert "<code>code</code>" in out


def test_text_to_html_passes_through_existing_html():
    html = "<h2>Title</h2><p>Body</p>"
    assert _text_to_html(html) == html


def test_create_note_autogenerates_slug_and_excerpt(db):
    note = db.create_note(title="Hello World", body="Some body text here.",
                          date="2026-01-15")
    assert note["slug"] == "2026-01-15-hello-world"
    assert note["excerpt"]
    assert "<p>Some body text here.</p>" in note["body_html"]


def test_update_note_converts_body_to_html(db):
    note = db.create_note(title="N", body="orig", date="2026-01-15")
    updated = db.update_note(note["slug"], body="updated **text**")
    assert "<strong>text</strong>" in updated["body_html"]

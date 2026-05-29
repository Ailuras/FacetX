"""End-to-end tests for the HTTP server: routing, CRUD, and connection reuse.

The server installs signal handlers, which only work on the main thread, so it
is launched as a subprocess with its own DOCSBOT_DATA_DIR.
"""

from __future__ import annotations

import json
import os
import signal
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request

import pytest


def _free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def _req(method, url, body=None):
    data = json.dumps(body).encode() if body is not None else None
    headers = {"Content-Type": "application/json"} if data else {}
    r = urllib.request.Request(url, data=data, headers=headers, method=method)
    with urllib.request.urlopen(r, timeout=5) as resp:
        return resp.status, json.loads(resp.read() or b"{}")


@pytest.fixture
def server(tmp_path):
    """Launch DocsBot as a subprocess with a seeded project; yield base URL."""
    data_dir = tmp_path / "docsbot"
    env = dict(os.environ, DOCSBOT_DATA_DIR=str(data_dir))

    # Create a project in-process (shares the same env var).
    os.environ["DOCSBOT_DATA_DIR"] = str(data_dir)
    import importlib
    import docsbot.config as config
    importlib.reload(config)
    config.create_project(name="Test Proj")

    port = _free_port()
    proc = subprocess.Popen(
        [sys.executable, "-m", "docsbot.cli", "serve", "--port", str(port)],
        env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    base = f"http://127.0.0.1:{port}"
    # Wait for the port to accept connections.
    for _ in range(50):
        try:
            urllib.request.urlopen(base + "/api/projects", timeout=1)
            break
        except (urllib.error.URLError, ConnectionError):
            time.sleep(0.1)
    else:
        proc.kill()
        pytest.fail("server did not start")

    yield base, proc, "test-proj"

    proc.send_signal(signal.SIGTERM)
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()


def test_list_projects(server):
    base, _proc, pid = server
    status, data = _req("GET", f"{base}/api/projects")
    assert status == 200
    assert any(p["id"] == pid for p in data["projects"])


def test_task_crud_round_trip(server):
    base, _proc, pid = server
    # Create
    status, task = _req("POST", f"{base}/api/projects/{pid}/tasks",
                        {"title": "do thing", "priority": "high"})
    assert status == 201
    tid = task["id"]
    # Read
    _, got = _req("GET", f"{base}/api/projects/{pid}/tasks/{tid}")
    assert got["title"] == "do thing"
    # Update
    _, upd = _req("PUT", f"{base}/api/projects/{pid}/tasks/{tid}",
                  {"status": "done"})
    assert upd["status"] == "done"
    # Delete
    _, deleted = _req("DELETE", f"{base}/api/projects/{pid}/tasks/{tid}")
    assert deleted["ok"] is True


def test_unknown_project_returns_404(server):
    base, _proc, _pid = server
    with pytest.raises(urllib.error.HTTPError) as exc:
        _req("GET", f"{base}/api/projects/nope/tasks")
    assert exc.value.code == 404


def test_no_connection_leak_under_load(server):
    base, proc, pid = server
    # Skip gracefully if lsof is unavailable.
    if subprocess.run(["which", "lsof"], capture_output=True).returncode != 0:
        pytest.skip("lsof not available")

    for _ in range(40):
        _req("GET", f"{base}/api/projects/{pid}/tasks")
        _req("GET", f"{base}/api/projects")
    time.sleep(0.3)

    out = subprocess.run(["lsof", "-p", str(proc.pid)],
                         capture_output=True, text=True).stdout
    open_dbs = sum(1 for ln in out.splitlines() if "db.sqlite" in ln)
    assert open_dbs <= 2, f"leaked {open_dbs} db connections"

import sys
from pathlib import Path

from fastapi.testclient import TestClient

# Tests import `main` from the parent directory, which is why pytest must run
# from api/ -- see AGENTS.md § Verifying before you push.
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from main import app  # noqa: E402

client = TestClient(app)


def test_health():
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_ready():
    response = client.get("/ready")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}

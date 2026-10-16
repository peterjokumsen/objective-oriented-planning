# Phase 1 · Step 5 — Skeleton API

Two routes, nothing else. No Cosmos client, no config module, no domain types —
those are Phase 2.

## `api/main.py`

```python
from fastapi import FastAPI

app = FastAPI()


@app.get("/health")
def health():
    return {"status": "ok"}


@app.get("/ready")
def ready():
    return {"status": "ok"}
```

## `api/requirements.txt`

Pin everything. An unpinned `fastapi` makes a container rebuild a different app,
which is the class of bug that only shows up in production.

```text
fastapi==0.116.1
uvicorn[standard]==0.35.0
httpx==0.28.1
pytest==8.3.4
```

`httpx` is required by FastAPI's `TestClient`; without it the tests fail on
import, which reads like a FastAPI problem and is not one.

## `api/Dockerfile`

```dockerfile
FROM python:3.11-slim
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1
WORKDIR /app
COPY requirements.txt ./
RUN pip install --no-cache-dir --root-user-action=ignore -r requirements.txt
COPY main.py ./
RUN useradd -m appuser && chown -R appuser /app
USER appuser
EXPOSE 8000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
```

Non-root, and `PYTHONUNBUFFERED=1` — without it uvicorn's logs sit in a buffer
and Log Analytics shows nothing useful after a crash. That is the whole point of
wiring Log Analytics in step 4.

Do **not** `COPY . .`: the build context is `api/` and `.dockerignore` excludes
tests, so keep the copy explicit.

## `api/.dockerignore`

```text
__pycache__/
*.py[cod]
.pytest_cache/
.ruff_cache/
.venv/
venv/
.env
.env.*
tests/
.git/
.vscode/
```

## `api/tests/test_main.py`

```python
import sys
from pathlib import Path

from fastapi.testclient import TestClient

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
```

The `sys.path` insert plus the `noqa: E402` is why the import resolves without an
installed package. Note it makes `pytest` work from **any** working directory —
it does not force you into `api/`. Run it from `api/` anyway, because that is
CI's `working-directory` (`AGENTS.md` § Verifying before you push), and running
it the same way locally is what makes a local pass mean anything.

## Verify

- `pytest -q` from `api/` — 2 passed. It also passes from the repo root,
  because the `sys.path` insert works from anywhere; run it from `api/` to match
  CI rather than treating either location as required.
- `pre-commit run --all-files` is clean for `api/`, or fix locally and re-run:
  `pre-commit run --files api/main.py api/tests/test_main.py`.
- `docker build -t oop-api:test ./api` succeeds and
  `docker run --rm -p 8000:8000 oop-api:test` answers `/health` — this catches
  the image before ACR ever sees it.

FROM python:3.11-slim
# PYTHONUNBUFFERED matters: without it uvicorn's logs sit in a buffer and Log
# Analytics shows nothing useful after a crash, which defeats wiring the
# workspace into the managed environment in the first place.
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1
WORKDIR /app
COPY requirements.txt ./
RUN pip install --no-cache-dir --root-user-action=ignore -r requirements.txt
# Explicit COPY, not `COPY . .`: the build context is api/ and .dockerignore
# excludes tests and caches.
COPY main.py ./
RUN useradd -m appuser && chown -R appuser /app
USER appuser
EXPOSE 8000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]

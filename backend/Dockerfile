# Multi-stage or standalone Python + uv container for Render
FROM python:3.12-slim

# Set environment variables
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy

WORKDIR /app

# Install uv binary directly from official image
COPY --from=ghcr.io/astral-sh/uv:0.5.24 /uv /uvx /bin/

# Copy dependency files first for layer caching
COPY pyproject.toml uv.lock ./

# Install dependencies using uv frozen sync
RUN uv sync --frozen --no-install-project --no-dev

# Copy application source code
COPY app/ ./app/

# Place virtualenv binaries on PATH
ENV PATH="/app/.venv/bin:$PATH"

EXPOSE 8000

# Start FastAPI relay server on the Render PORT (defaulting to 8000)
CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}"]

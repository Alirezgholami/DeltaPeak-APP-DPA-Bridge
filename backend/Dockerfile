FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt \
    && useradd --uid 10001 --create-home --shell /usr/sbin/nologin dpa
COPY --chown=dpa:dpa app ./app
COPY --chown=dpa:dpa scripts ./scripts
COPY --chown=dpa:dpa alembic.ini ./alembic.ini
COPY --chown=dpa:dpa migrations ./migrations

USER dpa
EXPOSE 8080
CMD ["sh", "-c", "alembic upgrade head && exec uvicorn app.main:app --host 0.0.0.0 --port 8080 --proxy-headers --forwarded-allow-ips=${DPA_FORWARDED_ALLOW_IPS:-127.0.0.1}"]

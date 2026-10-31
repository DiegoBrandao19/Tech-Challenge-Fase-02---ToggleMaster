# syntax=docker/dockerfile:1
# ---- Stage 1: instala dependências em /install ----
FROM python:3.11-slim AS builder
WORKDIR /build
COPY requirements.txt .
# Werkzeug<3: Flask 2.2.2 não é compatível com Werkzeug 3.x (url_quote removido)
RUN  pip install --no-cache-dir --prefix=/install -r requirements.txt "Werkzeug==2.2.3"

# ---- Stage 2: runtime enxuto, usuário não-root ----
FROM python:3.11-slim
RUN useradd --system --uid 10001 --no-create-home appuser
WORKDIR /app
COPY --from=builder /install /usr/local
COPY . .
ENV PYTHONUNBUFFERED=1 \
    PORT=8002
EXPOSE 8002
USER appuser
CMD ["sh", "-c", "exec gunicorn --bind 0.0.0.0:${PORT} --workers 2 app:app"]

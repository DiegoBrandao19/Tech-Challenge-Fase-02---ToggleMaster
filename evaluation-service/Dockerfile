# syntax=docker/dockerfile:1
# ---- Stage 1: build ----
FROM golang:1.22-alpine AS build
WORKDIR /src
COPY . .
# O go.sum original do repositório está corrompido (é cópia do go.mod); o tidy o regenera
RUN go mod tidy && \
    CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/evaluation-service .

# ---- Stage 2: runtime mínimo ----
# distroless/static já inclui os certificados CA (necessário para falar com o SQS via HTTPS)
FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/evaluation-service /evaluation-service
ENV PORT=8004
EXPOSE 8004
USER nonroot:nonroot
ENTRYPOINT ["/evaluation-service"]

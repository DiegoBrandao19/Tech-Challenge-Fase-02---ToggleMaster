# syntax=docker/dockerfile:1
# ---- Stage 1: build ----
FROM golang:1.22-alpine AS build
WORKDIR /src
COPY . .
# O repositório não traz go.sum; o tidy resolve e gera as somas
RUN go mod tidy && \
    CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/auth-service .

# ---- Stage 2: runtime mínimo (sem shell, usuário não-root) ----
FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/auth-service /auth-service
ENV PORT=8001
EXPOSE 8001
USER nonroot:nonroot
ENTRYPOINT ["/auth-service"]

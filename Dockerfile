# Vibe Server Dockerfile — 多阶段构建
# Go 1.26+，静态编译

FROM golang:1.26-alpine AS builder

RUN apk add --no-cache git ca-certificates tzdata

WORKDIR /build

# 缓存依赖
COPY go.mod go.sum ./
RUN go mod download

# 编译
COPY . .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -ldflags="-s -w" -o /vibe-server ./cmd/server/

# --- 运行镜像 ---
FROM alpine:3.20

RUN apk add --no-cache ca-certificates tzdata curl

ENV TZ=Asia/Shanghai
ENV GIN_MODE=release

WORKDIR /app
COPY --from=builder /vibe-server /app/vibe-server
COPY --from=builder /build/config.prod.yaml /app/config.yaml
COPY --from=builder /build/migrations /app/migrations

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -sf http://localhost:8080/api/health || exit 1

ENTRYPOINT ["/app/vibe-server"]

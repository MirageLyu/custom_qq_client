# Stage 1: 编译 Rust qq-client 二进制
FROM rust:latest AS builder

WORKDIR /build

# 先复制依赖清单，利用 Docker 层缓存
COPY Cargo.toml Cargo.lock* ./
RUN mkdir src && echo 'fn main() {}' > src/main.rs
RUN cargo build --release 2>/dev/null || true

# 复制完整源码并编译
COPY src/ ./src/
RUN touch src/main.rs && cargo build --release

# Stage 2: 基于 OpenClaw 官方镜像，注入 qq-client
FROM ghcr.io/openclaw/openclaw:latest

COPY --from=builder /build/target/release/qq-client /usr/local/bin/qq-client

COPY config.toml /app/config.toml

RUN mkdir -p /app/data

ENV OPENCLAW_SERVICE_KIND=gateway

WORKDIR /app

FROM ubuntu:24.04

RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    git \
    python3 \
    python3-pip \
    curl \
    netcat-openbsd \
    rustc \
    cargo \
    golang-go \
    clang \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace

COPY workspace/ /workspace/

# Create a simple public directory for static file tests
RUN mkdir -p /workspace/public && \
    echo "<h1>Welcome</h1>" > /workspace/public/index.html && \
    echo "static content" > /workspace/public/test.txt

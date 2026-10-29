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
    bc \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace

COPY workspace/ /workspace/

# Static fixtures are committed under workspace/public/ and copied above.
# (public/index.html and public/test.txt are served by the mini-http server.)

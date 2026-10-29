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

# Static files used by the verifier are also committed under workspace/public/.
RUN mkdir -p /workspace/public

#!/bin/bash
set -euo pipefail

SCORE=0.0
PORT=18080
BINARY=./mini-http

cd /workspace

# --- Build ---
if [ -f Makefile ]; then
  make -j$(nproc) || { echo "Build failed"; exit 1; }
elif [ -f Cargo.toml ]; then
  cargo build --release || exit 1
  cp target/release/mini-http ./mini-http || true
elif [ -f go.mod ]; then
  go build -o mini-http . || exit 1
else
  echo "No recognized build system"
  exit 1
fi

if [ ! -x "$BINARY" ]; then
  echo "Binary mini-http not found"
  exit 1
fi

# Start server in background
$BINARY --port $PORT\tableofcontents\tableofcontents\tableofcontents\tableofcontents\tableofcontents\tableofcontents\tableofcontents\tableofcontents\tableofcontents\tableofcontents\tableofcontents\tableofcontents\tableofcontents\tableofcontents\tableofcontents\tableofcontents\tableofcontents\tableofcontents\tableofcontents\tableofcontents\tableofcontents\tableofcontents\tableofcontents\tableofcontents\tableofcontents\tableofcontents\tableofcontents\tableofcontents\tableofcontents\tableofcontents\tableofcontents\tableofcontents\tableofcontents\tableofcontents\tableofcontents\tableofcontents\tableofcontents\tableofcontents\tableofcontents\tableofcontents\tableofcontents\tableofcontents\tableofcontents\tableofcontents\tableofcontents\tableofcontents\tableofcontents\tableofcontents\tableofcontents\tableofcontents\tableofcontents\tableofcontents\tableofcontents\tableofcontentsserver.log 2>&1 &
SERVER_PID=$!
sleep 1

cleanup() {
  kill $SERVER_PID 2>/dev/null || true
  wait $SERVER_PID 2>/dev/null || true
}
trap cleanup EXIT

# Helper
http_get() {
  curl -s -o /tmp/body -w "%{http_code}" --max-time 3 "http://127.0.0.1:$PORT$1" || echo "000"
}

http_post() {
  curl -s -o /tmp/body -w "%{http_code}" --max-time 3 -X POST -d "$2" "http://127.0.0.1:$PORT$1" || echo "000"
}

# Test 1: /hello (0.25)
CODE=$(http_get /hello)
BODY=$(cat /tmp/body)
if [ "$CODE" = "200" ] && echo "$BODY" | grep -q "Hello, World!"; then
  SCORE=$(echo "$SCORE + 0.25" | bc)
  echo "PASS: /hello"
else
  echo "FAIL: /hello (code=$CODE)"
fi

# Test 2: static file (0.20)
CODE=$(http_get /)
BODY=$(cat /tmp/body)
if [ "$CODE" = "200" ] && echo "$BODY" | grep -q "Welcome"; then
  SCORE=$(echo "$SCORE + 0.20" | bc)
  echo "PASS: static index.html"
else
  echo "FAIL: static index.html"
fi

# Test 3: echo query (0.15)
CODE=$(http_get "/echo?msg=frontier")
BODY=$(cat /tmp/body)
if [ "$CODE" = "200" ] && echo "$BODY" | grep -q "frontier"; then
  SCORE=$(echo "$SCORE + 0.15" | bc)
  echo "PASS: /echo"
else
  echo "FAIL: /echo"
fi

# Test 4: POST body (0.15)
CODE=$(http_post /submit "secret-payload-42")
BODY=$(cat /tmp/body)
if [ "$CODE" = "200" ] && echo "$BODY" | grep -q "secret-payload-42"; then
  SCORE=$(echo "$SCORE + 0.15" | bc)
  echo "PASS: POST /submit"
else
  echo "FAIL: POST /submit"
fi

# Test 5: 404 (0.10)
CODE=$(http_get /does-not-exist)
if [ "$CODE" = "404" ]; then
  SCORE=$(echo "$SCORE + 0.10" | bc)
  echo "PASS: 404"
else
  echo "FAIL: 404 (got $CODE)"
fi

# Test 6: concurrent requests (0.15)
success=0
for i in $(seq 1 30); do
  CODE=$(http_get /hello)
  if [ "$CODE" = "200" ]; then
    success=$((success+1))
  fi
done
if [ $success -ge 25 ]; then
  SCORE=$(echo "$SCORE + 0.15" | bc)
  echo "PASS: concurrency ($success/30)"
else
  echo "FAIL: concurrency ($success/30)"
fi

echo "Final score: $SCORE"
mkdir -p /logs/verifier
echo "$SCORE" > /logs/verifier/reward.txt
echo "Mean: $SCORE"

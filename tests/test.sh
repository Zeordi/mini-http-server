#!/bin/bash
# FrontierSWE / Harbor verifier for mini-http-server.
# Builds the agent's server, starts it, runs a comprehensive HTTP/1.1 test
# suite, and ALWAYS writes the final fractional score to
# /logs/verifier/reward.txt (even on build/start failure).
set -uo pipefail

PORT=18080
BINARY=./mini-http
LOGDIR=/logs/verifier
REWARD="$LOGDIR/reward.txt"

mkdir -p "$LOGDIR"

# Always write a reward file, even if something goes wrong.
write_reward() {
    # $1 = score in hundredths (0..100)
    local h=$1
    local int=$(( h / 100 ))
    local frac=$(( h % 100 ))
    printf "%d.%02d\n" "$int" "$frac" > "$REWARD"
}

fail() {
    trap - EXIT TERM INT
    write_reward 0
    echo "FATAL: $*"
    exit 0
}

cd /workspace

# ---------------- Build ----------------
SCORE=0 # hundredths

if [ -f Makefile ]; then
    make -j"$(nproc)" > /tmp/build.log 2>&1 || fail "build failed (make)"
elif [ -f Cargo.toml ]; then
    cargo build --release > /tmp/build.log 2>&1 || fail "build failed (cargo)"
    cp target/release/mini-http ./mini-http 2>/dev/null || cp target/release/mini-http.exe ./mini-http 2>/dev/null || true
elif [ -f go.mod ]; then
    go build -o mini-http . > /tmp/build.log 2>&1 || fail "build failed (go)"
else
    fail "no recognized build system (Makefile / Cargo.toml / go.mod)"
fi

if [ ! -x "$BINARY" ]; then
    fail "binary mini-http not found after build"
fi

# ---------------- Start server ----------------
rm -f /tmp/server.log
"$BINARY" --port "$PORT" > /tmp/server.log 2>&1 &
SERVER_PID=$!
sleep 1

cleanup() {
    kill "$SERVER_PID" >/dev/null 2>&1 || true
    wait "$SERVER_PID" >/dev/null 2>&1 || true
}
trap 'cleanup; write_reward "$SCORE"' EXIT TERM INT

if ! kill -0 "$SERVER_PID" >/dev/null 2>&1; then
    fail "server exited immediately (see /tmp/server.log)"
fi

# ---------------- Helpers ----------------
# http_get PATH -> sets HTTP_CODE and HTTP_BODY globals
http_get() {
    HTTP_BODY=$(curl -s -o /tmp/resp.body -w "%{http_code}" --max-time 5 --connect-timeout 2 "http://127.0.0.1:$PORT$1" 2>/dev/null) || HTTP_BODY="000"
    HTTP_CODE="${HTTP_BODY: -3}"
    HTTP_BODY=$(cat /tmp/resp.body 2>/dev/null)
}

http_post() {
    # $1 path, $2 body
    HTTP_BODY=$(curl -s -o /tmp/resp.body -w "%{http_code}" --max-time 5 --connect-timeout 2 \
        -X POST -d "$2" "http://127.0.0.1:$PORT$1" 2>/dev/null) || HTTP_BODY="000"
    HTTP_CODE="${HTTP_BODY: -3}"
    HTTP_BODY=$(cat /tmp/resp.body 2>/dev/null)
}

assert_contains() {
    # $1 test name, $2 points, $3 code, $4 body, $5 needle
    local name="$1" pts="$2" code="$3" body="$4" needle="$5"
    if [ "$code" = "200" ] && printf '%s' "$body" | grep -qF "$needle"; then
        SCORE=$((SCORE + pts))
        echo "PASS: $name"
    else
        echo "FAIL: $name (code=$code)"
    fi
}

assert_code() {
    local name="$1" pts="$2" code="$3" want="$4"
    if [ "$code" = "$want" ]; then
        SCORE=$((SCORE + pts))
        echo "PASS: $name"
    else
        echo "FAIL: $name (code=$code, want=$want)"
    fi
}

# ---------------- Tests ----------------

# 1. GET /hello  (14)
http_get /hello
assert_contains "/hello" 14 "$HTTP_CODE" "$HTTP_BODY" "Hello, World!"

# 2. GET / -> index.html  (11)
http_get /
assert_contains "GET / index.html" 11 "$HTTP_CODE" "$HTTP_BODY" "Welcome"

# 3. GET /test.txt static  (10)
http_get /test.txt
assert_contains "GET /test.txt static" 8 "$HTTP_CODE" "$HTTP_BODY" "static content"

# 4. GET /echo?msg=frontier  (10)
http_get "/echo?msg=frontier"
assert_contains "/echo query" 8 "$HTTP_CODE" "$HTTP_BODY" "frontier"

# 5. POST /submit body echo  (10)
http_post /submit "secret-payload-42"
assert_contains "POST /submit body" 8 "$HTTP_CODE" "$HTTP_BODY" "secret-payload-42"

# 6. POST /submit chunked request body  (5)
{
    exec 3<>/dev/tcp/127.0.0.1/"$PORT"
    printf 'POST /submit HTTP/1.1\r\nHost: 127.0.0.1\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhello\r\n6\r\n world\r\n0\r\n\r\n' >&3
    # read status line
    CFD_CODE=""
    if read -r -t 5 line <&3; then
        set -- $line
        CFD_CODE="$2"
    fi
    # read headers to find Content-Length of the echoed body
    CL=0
    while read -r -t 5 hdr <&3; do
        hdr="${hdr%$'\r'}"
        [ -z "$hdr" ] && break
        case "$hdr" in
            Content-Length:*) CL="${hdr#*:}"; CL="${CL// /}" ;;
        esac
    done
    CFD_BODY=""
    if [ "$CL" -gt 0 ] 2>/dev/null; then
        read -r -n "$CL" -t 5 CFD_BODY <&3 || true
    fi
    exec 3<&- 3>&- || true
} 2>/dev/null
if [ "${CFD_CODE:-}" = "200" ] && [ "${CFD_BODY:-}" = "hello world" ]; then
    SCORE=$((SCORE + 5))
    echo "PASS: POST /submit chunked request body"
else
    echo "FAIL: POST /submit chunked request body (code=${CFD_CODE:-none}, body=${CFD_BODY:-none})"
fi

# 7. GET /missing -> 404  (8)
http_get /does-not-exist-xyz
assert_code "GET unknown -> 404" 8 "$HTTP_CODE" 404

# 8. POST /hello -> 405  (4)
http_post /hello "x"
assert_code "POST /hello -> 405" 4 "$HTTP_CODE" 405

# 9. GET /submit -> 405  (4)
http_get /submit
assert_code "GET /submit -> 405" 4 "$HTTP_CODE" 405

# 10. GET /hello with X-Chunked: 1 -> chunked response with Transfer-Encoding header  (6)
HTTP_RC=$(curl -s -D /tmp/resp.headers -o /tmp/resp.body -w "%{http_code}" --max-time 5 --connect-timeout 2 \
    -H "X-Chunked: 1" "http://127.0.0.1:$PORT/hello" 2>/dev/null) || HTTP_RC="000"
CHUNK_CODE="${HTTP_RC: -3}"
CHUNK_BODY=$(cat /tmp/resp.body 2>/dev/null)
CHUNK_HEADERS=$(cat /tmp/resp.headers 2>/dev/null)
if [ "$CHUNK_CODE" = "200" ] && printf '%s' "$CHUNK_HEADERS" | grep -qi 'Transfer-Encoding: chunked' && printf '%s' "$CHUNK_BODY" | grep -qF "Hello, World!"; then
    SCORE=$((SCORE + 6))
    echo "PASS: chunked response (X-Chunked: Transfer-Encoding: chunked)"
else
    echo "FAIL: chunked response (code=$CHUNK_CODE)"
fi

# 11. Persistent connection: two requests on one TCP connection  (4)
{
    exec 4<>/dev/tcp/127.0.0.1/"$PORT"
    printf 'GET /hello HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: keep-alive\r\n\r\nGET /hello HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: keep-alive\r\n\r\n' >&4
    c1=""; c2=""
    # response 1 status
    if read -r -t 5 line <&4; then
        set -- $line; c1="$2"
    fi
    # consume response 1 headers + body
    cl=0
    while read -r -t 5 hdr <&4; do
        hdr="${hdr%$'\r'}"
        [ -z "$hdr" ] && break
        case "$hdr" in
            Content-Length:*) cl="${hdr#*:}"; cl="${cl// /}" ;;
        esac
    done
    if [ "$cl" -gt 0 ] 2>/dev/null; then
        read -r -n "$cl" -t 5 _ <&4 || true
    fi
    # response 2 status
    if read -r -t 5 line <&4; then
        set -- $line; c2="$2"
    fi
    exec 4<&- 4>&- || true
} 2>/dev/null
if [ "$c1" = "200" ] && [ "$c2" = "200" ]; then
    SCORE=$((SCORE + 4))
    echo "PASS: persistent connection (keep-alive)"
else
    echo "FAIL: persistent connection (c1=$c1 c2=$c2)"
fi

# 12. Connection: close closes the connection  (4)
{
    exec 5<>/dev/tcp/127.0.0.1/"$PORT"
    printf 'GET /hello HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n' >&5
    closed=0
    code=""
    if read -r -t 5 line <&5; then
        set -- $line
        code="$2"
    fi
    cl=0
    while read -r -t 5 hdr <&5; do
        hdr="${hdr%$'\r'}"
        [ -z "$hdr" ] && break
        case "$hdr" in
            Content-Length:*) cl="${hdr#*:}"; cl="${cl// /}" ;;
        esac
    done
    if [ "$cl" -gt 0 ] 2>/dev/null; then
        read -r -n "$cl" -t 5 body <&5 || true
    fi
    # now that the full response is consumed, the server should have closed
    if ! read -r -t 2 extra <&5; then
        closed=1
    fi
    exec 5<&- 5>&- || true
} 2>/dev/null
if [ "$code" = "200" ] && [ "$closed" = "1" ]; then
    SCORE=$((SCORE + 4))
    echo "PASS: Connection: close closes connection"
else
    echo "FAIL: Connection: close (code=$code closed=$closed)"
fi

# 13. Malformed request -> 400  (6)
{
    exec 6<>/dev/tcp/127.0.0.1/"$PORT"
    printf 'NOTANHTTPREQUEST\r\n\r\n' >&6
    mcode=""
    if read -r -t 5 mline <&6; then
        set -- $mline
        mcode="$2"
    fi
    exec 6<&- 6>&- || true
} 2>/dev/null
{
    exec 6<>/dev/tcp/127.0.0.1/"$PORT"
    printf 'GET /\r\n\r\n' >&6
    mcode2=""
    if read -r -t 5 mline <&6; then
        set -- $mline
        mcode2="$2"
    fi
    exec 6<&- 6>&- || true
} 2>/dev/null
if [ "$mcode" = "400" ] && [ "$mcode2" = "400" ]; then
    SCORE=$((SCORE + 6))
    echo "PASS: malformed request -> 400"
else
    echo "FAIL: malformed request (code=${mcode:-none}, code2=${mcode2:-none})"
fi

# 14. Concurrency: 50 parallel GET /hello, at least 45 must succeed  (10)
success=0
pids=""
for i in $(seq 1 50); do
    (
        http_get /hello
        if [ "$HTTP_CODE" = "200" ]; then
            echo "1"
        else
            echo "0"
        fi
    ) > /tmp/conc.$i &
    pids="$pids $!"
done
for p in $pids; do
    wait "$p" 2>/dev/null || true
done
for i in $(seq 1 50); do
    if [ -f /tmp/conc.$i ] && [ "$(cat /tmp/conc.$i)" = "1" ]; then
        success=$((success + 1))
    fi
    rm -f /tmp/conc.$i
done
if [ "$success" -ge 45 ]; then
    SCORE=$((SCORE + 10))
    echo "PASS: concurrency ($success/50)"
else
    echo "FAIL: concurrency ($success/50)"
fi

# ---------------- Final ----------------
echo "------------------------------"
echo "Final score: $SCORE / 100"
write_reward "$SCORE"
int=$(( SCORE / 100 ))
frac=$(( SCORE % 100 ))
printf 'Mean: %d.%02d\n' "$int" "$frac"

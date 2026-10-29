# Mini HTTP/1.1 Server from Scratch

Implement a correct HTTP/1.1 server **from scratch** using only raw TCP sockets. You may use the standard library, but you may NOT use any existing HTTP server implementation, web framework, or networking framework that provides HTTP (e.g. no `net/http` server in Go, no `actix-web`/`hyper`/`warp` in Rust, no `Flask`/`Django` in Python, no `Express` in Node, no `boost::beast` HTTP server, etc.). Using `net.Listen`/`net.Conn` (Go), `TcpListener`/`TcpStream` (Rust), or raw `socket`/`bind`/`listen`/`accept` (C/C++) is expected and required.

## Binary

- The compiled binary must be named exactly `mini-http`.
- It must be invocable as `./mini-http --port <port>` (default port 8080).
- A working build must be reproducible from the workspace root via `make`, `cargo build --release`, or `go build -o mini-http .` — pick one and provide the corresponding build file (`Makefile`, `Cargo.toml`, or `go.mod`).

## Required features

Your server must implement all of the following:

1. **HTTP/1.1 parsing** — parse the request line (`METHOD PATH HTTP/1.1`), headers (case-insensitive, `\r\n` terminated), and the message body.
2. **Persistent connections (keep-alive)** — by default (`Connection: keep-alive`, the HTTP/1.1 default) the server must serve multiple requests on the same TCP connection and only close when the client sends `Connection: close` or disconnects.
3. **`Connection: close`** — honor it and close the connection cleanly after the current response.
4. **Content-Length** — all responses must include a correct `Content-Length` header (or valid chunked transfer encoding, see below).
5. **Chunked transfer encoding** — the server must correctly read a chunked request body (`Transfer-Encoding: chunked`) and MUST be able to produce a chunked response when the client requests it (see the `X-Chunked` header below).
6. **Static file serving** — serve files from a `./public` directory relative to the current working directory. Map URL paths to files under `public/` (e.g. `GET /test.txt` → `public/test.txt`). Prevent directory traversal (`..` must not escape `public/`).
7. **Routes**:
   - `GET /` → return `public/index.html` with status 200.
   - `GET /hello` → return plain text `Hello, World!` with status 200.
   - `GET /echo?msg=...` → return the (URL-decoded) value of the `msg` query parameter with status 200. If `msg` is absent, return an empty body with status 200.
   - `POST /submit` → read the request body (Content-Length or chunked) and return it verbatim with status 200 and `Content-Type: text/plain`.
8. **Status codes**:
   - `200` for successful requests.
   - `400` for malformed/unparseable requests.
   - `404` for unknown paths / missing static files.
   - `405` when a known route is requested with an unsupported method (e.g. `POST /hello`, `GET /submit`).
   - `500` for server errors (e.g. unreadable static file).
9. **Concurrency** — handle at least 50 simultaneous client connections without crashing or deadlocking.
10. **Clean shutdown of idle connections** — do not hang forever waiting on an idle keep-alive connection; use read timeouts.

## Chunked response trigger

To make chunked response encoding testable deterministically, the server must respond with `Transfer-Encoding: chunked` (instead of `Content-Length`) when the request includes the header `X-Chunked: 1`. The chunked body must still contain the exact same payload (a test harness using curl will transparently decode it and compare the body).

## Constraints

- Language: C, C++, Rust, or Go (recommended).
- Standard library + raw sockets only. No HTTP server libraries/frameworks.
- Binary name: `mini-http`.
- CLI argument: `--port <number>`.
- The server must run in the foreground and bind to `0.0.0.0` (or `127.0.0.1`).

## Example

```bash
./mini-http --port 18080
```

Then in another terminal:

```bash
curl -i http://127.0.0.1:18080/hello
curl -i -d 'payload' http://127.0.0.1:18080/submit
curl -i -H 'X-Chunked: 1' http://127.0.0.1:18080/echo?msg=hi
```

## How you are scored

The verifier builds your code, starts `./mini-http --port <PORT>`, runs a test harness (`tests/test.sh`) that checks routes, static files, POST body (Content-Length and chunked), 404, 405, 400, persistent connections, `Connection: close`, chunked responses, and concurrency, then writes a fractional score in `[0, 1]` to `/logs/verifier/reward.txt`. A correct, complete implementation scores `1.0`.

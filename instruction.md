# Mini HTTP/1.1 Server from Scratch

Implement a correct HTTP/1.1 server **from scratch** (no frameworks, no `http` standard library servers, no third-party web libraries).

## Mandatory features

Your server must:

1. Listen on a configurable port (default 8080)
2. Speak HTTP/1.1 correctly
3. Support **persistent connections** (keep-alive)
4. Support **chunked transfer encoding** for responses
5. Serve static files from a `./public` directory
6. Support the following routes:
   - `GET /` → return `index.html` from public/
   - `GET /hello` → return plain text `Hello, World!`
   - `GET /echo?msg=...` → echo the query parameter
   - `POST /submit` → read the request body and return it with status 200
7. Handle at least 50 concurrent connections without crashing
8. Return proper status codes (200, 404, 405, 400, 500)
9. Include correct `Content-Length` or use chunked encoding
10. Close the connection cleanly on `Connection: close`

## Constraints

- Language: C, C++, Rust, or Go (preferred)
- You may use only the standard library + raw sockets
- No existing HTTP server libraries or frameworks
- The binary must be named `mini-http`
- It must accept `--port <number>` as a command-line argument

## Example usage

```bash
./mini-http --port 8080

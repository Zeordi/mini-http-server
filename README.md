# mini-http-server

A FrontierSWE / Harbor benchmark task: implement a correct HTTP/1.1 server from scratch using only raw TCP sockets.

## Task summary

The agent must implement a from-scratch HTTP/1.1 server named `mini-http` that accepts `--port` and supports:

- HTTP/1.1 request parsing (request line, headers, body)
- Persistent connections (keep-alive) and `Connection: close`
- `Content-Length` responses and chunked transfer encoding (both directions)
- Static file serving from `./public` with traversal protection
- Routes: `GET /`, `GET /hello`, `GET /echo?msg=`, `POST /submit`
- Status codes: 200, 400, 404, 405, 500
- Concurrent connections (50+)

Language: C, C++, Rust, or Go. Standard library + raw sockets only; no HTTP server frameworks.

## Repository layout

```
mini-http-server/
├── instruction.md          # full task specification given to the agent
├── task.toml               # FrontierSWE/Harbor task metadata
├── environment/
│   ├── Dockerfile          # verifier container image
│   └── workspace/          # what the agent sees (starter + public/)
│       ├── public/
│       │   ├── index.html
│       │   └── test.txt
│       └── README.md       # starter instructions for the agent
├── tests/
│   └── test.sh             # verifier (hidden from the agent)
├── solution/
│   └── solve.sh            # oracle reference solution (hidden from the agent)
├── README.md               # this file
└── .gitignore
```

## Verification

The verifier builds the agent's submission, launches `./mini-http --port <PORT>`, runs `tests/test.sh`, and reads the fractional score from `/logs/verifier/reward.txt`. A complete, correct implementation scores `1.0`.

## Required submission commands

```bash
python3 frontierswe-check.py .
harbor run -p . -a oracle
harbor run -p . -a nop
```

## RustLabs form values

- Kind of task: implementation (from-scratch network server)
- What the agent has to do: write a correct HTTP/1.1 server from raw sockets; verifier scores routes, static files, POST body (Content-Length + chunked), 404/405/400, keep-alive, `Connection: close`, chunked responses, and concurrency, writing a score in [0,1] to /logs/verifier/reward.txt
- Estimated time: 6–12 hours for a strong engineer
- Oracle score: 1.0
- Empty-agent score: 0.0

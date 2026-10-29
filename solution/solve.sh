#!/bin/bash
set -euo pipefail

cat > /workspace/main.go << 'EOF'
package main

import (
	"bufio"
	"fmt"
	"io"
	"net"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
)

func main() {
	port := "8080"
	for i, arg := range os.Args {
		if arg == "--port" && i+1 < len(os.Args) {
			port = os.Args[i+1]
		}
	}

	ln, err := net.Listen("tcp", ":"+port)
	if err != nil {
		panic(err)
	}
	fmt.Println("Listening on", port)

	var wg sync.WaitGroup
	for {
		conn, err := ln.Accept()
		if err != nil {
			continue
		}
		wg.Add(1)
		go func(c net.Conn) {
			defer wg.Done()
			handle(c)
		}(conn)
	}
}

func handle(conn net.Conn) {
	defer conn.Close()
	reader := bufio.NewReader(conn)

	for {
		// Request line
		line, err := reader.ReadString('\n')
		if err != nil {
			return
		}
		line = strings.TrimSpace(line)
		if line == "" {
			return
		}
		parts := strings.Fields(line)
		if len(parts) < 2 {
			writeResponse(conn, 400, "text/plain", "Bad Request")
			return
		}
		method, rawURL := parts[0], parts[1]

		// Headers
		headers := map[string]string{}
		contentLength := 0
		connectionClose := false
		for {
			h, err := reader.ReadString('\n')
			if err != nil {
				return
			}
			h = strings.TrimSpace(h)
			if h == "" {
				break
			}
			if kv := strings.SplitN(h, ":", 2); len(kv) == 2 {
				key := strings.ToLower(strings.TrimSpace(kv[0]))
				val := strings.TrimSpace(kv[1])
				headers[key] = val
				if key == "content-length" {
					contentLength, _ = strconv.Atoi(val)
				}
				if key == "connection" && strings.ToLower(val) == "close" {
					connectionClose = true
				}
			}
		}

		// Body
		var body []byte
		if contentLength > 0 {
			body = make([]byte, contentLength)
			io.ReadFull(reader, body)
		}

		// Routing
		u, _ := url.Parse(rawURL)
		path := u.Path

		switch {
		case method == "GET" && path == "/hello":
			writeResponse(conn, 200, "text/plain", "Hello, World!")
		case method == "GET" && path == "/echo":
			msg := u.Query().Get("msg")
			writeResponse(conn, 200, "text/plain", msg)
		case method == "POST" && path == "/submit":
			writeResponse(conn, 200, "text/plain", string(body))
		case method == "GET" && (path == "/" || path == "/index.html"):
			serveFile(conn, "public/index.html")
		case method == "GET":
			// try static
			fp := filepath.Join("public", filepath.Clean(path))
			if strings.HasPrefix(fp, "public") {
				if _, err := os.Stat(fp); err == nil {
					serveFile(conn, fp)
				} else {
					writeResponse(conn, 404, "text/plain", "Not Found")
				}
			} else {
				writeResponse(conn, 404, "text/plain", "Not Found")
			}
		default:
			writeResponse(conn, 405, "text/plain", "Method Not Allowed")
		}

		if connectionClose {
			return
		}
	}
}

func writeResponse(conn net.Conn, status int, contentType, body string) {
	statusText := map[int]string{
		200: "OK", 400: "Bad Request", 404: "Not Found",
		405: "Method Not Allowed", 500: "Internal Server Error",
	}[status]
	resp := fmt.Sprintf("HTTP/1.1 %d %s\r\n", status, statusText)
	resp += fmt.Sprintf("Content-Type: %s\r\n", contentType)
	resp += fmt.Sprintf("Content-Length: %d\r\n", len(body))
	resp += "Connection: keep-alive\r\n"
	resp += "\r\n"
	resp += body
	conn.Write([]byte(resp))
}

func serveFile(conn net.Conn, path string) {
	data, err := os.ReadFile(path)
	if err != nil {
		writeResponse(conn, 404, "text/plain", "Not Found")
		return
	}
	ct := "text/plain"
	if strings.HasSuffix(path, ".html") {
		ct = "text/html"
	}
	writeResponse(conn, 200, ct, string(data))
}
EOF

# Build the reference
cd /workspace
go mod init minihttp 2>/dev/null || true
go build -o mini-http .

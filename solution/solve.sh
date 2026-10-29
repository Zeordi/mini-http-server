#!/bin/bash
set -euo pipefail

cat > /workspace/main.go << 'EOF'
package main

import (
	"bufio"
	"fmt"
	"io"
	"log"
	"net"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

const (
	publicDir   = "public"
	readTimeout = 10 * time.Second
)

var errBadRequest = fmt.Errorf("400")

type request struct {
	method  string
	path    string
	query   url.Values
	body    []byte
	headers map[string]string
	close   bool
	chunked bool
}

func main() {
	port := "8080"
	for i := 1; i < len(os.Args); i++ {
		if os.Args[i] == "--port" && i+1 < len(os.Args) {
			port = os.Args[i+1]
			i++
		}
	}

	ln, err := net.Listen("tcp", ":"+port)
	if err != nil {
		log.Fatalf("listen: %v", err)
	}
	fmt.Printf("mini-http listening on :%s\n", port)

	for {
		conn, err := ln.Accept()
		if err != nil {
			continue
		}
		go handleConn(conn)
	}
}

func handleConn(conn net.Conn) {
	defer conn.Close()
	br := bufio.NewReader(conn)
	bw := bufio.NewWriter(conn)

	for {
		conn.SetReadDeadline(time.Now().Add(readTimeout))
		conn.SetWriteDeadline(time.Now().Add(readTimeout))

		req, err := readRequest(br)
		if err != nil {
			if err == errBadRequest {
				bw.Write([]byte("HTTP/1.1 400 Bad Request\r\nContent-Type: text/plain\r\nContent-Length: 11\r\nConnection: close\r\n\r\nBad Request"))
				bw.Flush()
			}
			return
		}

		resp := buildResponse(req)
		if _, err := bw.Write(resp); err != nil {
			return
		}
		if err := bw.Flush(); err != nil {
			return
		}

		if req.close {
			return
		}
	}
}

func readRequest(br *bufio.Reader) (*request, error) {
	line, err := br.ReadString('\n')
	if err != nil {
		return nil, err
	}
	line = strings.TrimRight(line, "\r\n")
	if line == "" {
		return nil, io.EOF
	}
	fields := strings.Fields(line)
	if len(fields) < 2 {
		return nil, errBadRequest
	}
	method := strings.ToUpper(fields[0])
	rawURL := fields[1]

	headers := map[string]string{}
	var contentLength int64 = -1
	connectionClose := false
	chunked := false

	for {
		h, err := br.ReadString('\n')
		if err != nil {
			return nil, err
		}
		h = strings.TrimRight(h, "\r\n")
		if h == "" {
			break
		}
		kv := strings.SplitN(h, ":", 2)
		if len(kv) != 2 {
			continue
		}
		key := strings.ToLower(strings.TrimSpace(kv[0]))
		val := strings.TrimSpace(kv[1])
		headers[key] = val
		switch key {
		case "content-length":
			if n, err := strconv.ParseInt(val, 10, 64); err == nil {
				contentLength = n
			}
		case "connection":
			if strings.ToLower(val) == "close" {
				connectionClose = true
			}
		case "transfer-encoding":
			if strings.ToLower(val) == "chunked" {
				chunked = true
			}
		}
	}

	var body []byte
	if chunked {
		body, err = readChunkedBody(br)
		if err != nil {
			return nil, err
		}
	} else if contentLength >= 0 {
		body = make([]byte, contentLength)
		if _, err := io.ReadFull(br, body); err != nil {
			return nil, err
		}
	}

	u, err := url.Parse(rawURL)
	path := u.Path
	if err != nil {
		path = rawURL
	}
	query := u.Query()

	return &request{
		method:  method,
		path:    path,
		query:   query,
		body:    body,
		headers: headers,
		close:   connectionClose,
		chunked: chunked,
	}, nil
}

func readChunkedBody(br *bufio.Reader) ([]byte, error) {
	var out []byte
	for {
		line, err := br.ReadString('\n')
		if err != nil {
			return nil, err
		}
		line = strings.TrimSpace(line)
		size, err := strconv.ParseInt(line, 16, 64)
		if err != nil {
			return nil, errBadRequest
		}
		if size == 0 {
			// read trailers until blank line
			for {
				t, err := br.ReadString('\n')
				if err != nil {
					return out, nil
				}
				t = strings.TrimRight(t, "\r\n")
				if t == "" {
					return out, nil
				}
			}
		}
		chunk := make([]byte, size)
		if _, err := io.ReadFull(br, chunk); err != nil {
			return nil, err
		}
		out = append(out, chunk...)
		// consume trailing CRLF after chunk data
		if _, err := br.ReadString('\n'); err != nil {
			return nil, err
		}
	}
}

func buildResponse(req *request) []byte {
	// Determine allowed methods per known route.
	allowed := map[string]string{
		"/":      "GET",
		"/hello": "GET",
		"/echo":  "GET",
		"/submit": "POST",
	}

	// Known-route method check.
	if _, known := allowed[req.path]; known {
		if req.method != allowed[req.path] {
			return statusResponse(405, "text/plain", "Method Not Allowed", req)
		}
	}

	switch {
	case req.method == "GET" && req.path == "/":
		return serveFile(req, filepath.Join(publicDir, "index.html"))
	case req.method == "GET" && req.path == "/hello":
		return statusResponse(200, "text/plain", "Hello, World!", req)
	case req.method == "GET" && req.path == "/echo":
		return statusResponse(200, "text/plain", req.query.Get("msg"), req)
	case req.method == "POST" && req.path == "/submit":
		return statusResponse(200, "text/plain", string(req.body), req)
	case req.method == "GET":
		// Static file.
		clean := filepath.Clean(req.path)
		if strings.Contains(clean, "..") {
			return statusResponse(404, "text/plain", "Not Found", req)
		}
		fp := filepath.Join(publicDir, clean)
		if !strings.HasPrefix(filepath.Clean(fp), publicDir+string(os.PathSeparator)) && fp != publicDir {
			return statusResponse(404, "text/plain", "Not Found", req)
		}
		return serveFile(req, fp)
	default:
		// Unknown path or disallowed method on unknown path.
		if req.method == "GET" {
			return statusResponse(404, "text/plain", "Not Found", req)
		}
		return statusResponse(404, "text/plain", "Not Found", req)
	}
}

func serveFile(req *request, path string) []byte {
	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return statusResponse(404, "text/plain", "Not Found", req)
		}
		return statusResponse(500, "text/plain", "Internal Server Error", req)
	}
	ct := contentType(path)
	return statusResponse(200, ct, string(data), req)
}

func contentType(path string) string {
	ext := strings.ToLower(filepath.Ext(path))
	switch ext {
	case ".html":
		return "text/html"
	case ".txt":
		return "text/plain"
	case ".css":
		return "text/css"
	case ".js":
		return "application/javascript"
	case ".json":
		return "application/json"
	case ".png":
		return "image/png"
	case ".jpg", ".jpeg":
		return "image/jpeg"
	default:
		return "application/octet-stream"
	}
}

func statusResponse(status int, contentType, body string, req *request) []byte {
	statusText := map[int]string{
		200: "OK", 400: "Bad Request", 404: "Not Found",
		405: "Method Not Allowed", 500: "Internal Server Error",
	}
	text, ok := statusText[status]
	if !ok {
		text = "OK"
	}

	var header strings.Builder
	header.WriteString(fmt.Sprintf("HTTP/1.1 %d %s\r\n", status, text))
	header.WriteString(fmt.Sprintf("Content-Type: %s\r\n", contentType))
	header.WriteString(fmt.Sprintf("Content-Length: %d\r\n", len(body)))
	if req.close {
		header.WriteString("Connection: close\r\n")
	} else {
		header.WriteString("Connection: keep-alive\r\n")
	}
	header.WriteString("\r\n")

	if req.headers["x-chunked"] == "1" {
		var out strings.Builder
		out.WriteString(fmt.Sprintf("HTTP/1.1 %d %s\r\n", status, text))
		out.WriteString(fmt.Sprintf("Content-Type: %s\r\n", contentType))
		out.WriteString("Transfer-Encoding: chunked\r\n")
		if req.close {
			out.WriteString("Connection: close\r\n")
		} else {
			out.WriteString("Connection: keep-alive\r\n")
		}
		out.WriteString("\r\n")
		bodyBytes := []byte(body)
		const chunkSize = 16
		for len(bodyBytes) > 0 {
			n := chunkSize
			if n > len(bodyBytes) {
				n = len(bodyBytes)
			}
			out.WriteString(fmt.Sprintf("%x\r\n", n))
			out.Write(bodyBytes[:n])
			out.WriteString("\r\n")
			bodyBytes = bodyBytes[n:]
		}
		out.WriteString("0\r\n\r\n")
		return []byte(out.String())
	}

	return []byte(header.String() + body)
}
EOF

# Build the reference solution
cd /workspace
go mod init minihttp 2>/dev/null || true
go build -o mini-http .

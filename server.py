#!/usr/bin/env python3
"""Minimal host HTTP server for remote shell file transfer."""

from __future__ import annotations

import argparse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, unquote, urlparse


DEFAULT_PORT = 8090


def safe_name(raw: str) -> str:
    if raw is None:
        raise ValueError("missing name")
    name = Path(unquote(raw)).name
    if not name or name in (".", "..") or "/" in name or "\\" in name:
        raise ValueError("invalid name")
    return name


def make_server(
    host: str,
    port: int,
    storage_dir: Path | None = None,
    clients_dir: Path | None = None,
) -> ThreadingHTTPServer:
    root = Path(__file__).resolve().parent
    storage = Path(storage_dir) if storage_dir else root / "storage"
    clients = Path(clients_dir) if clients_dir else root / "clients"
    storage.mkdir(parents=True, exist_ok=True)

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, fmt, *args):
            print(f"[host] {self.address_string()} {fmt % args}")

        def do_GET(self):
            parsed = urlparse(self.path)
            path = parsed.path

            if path.startswith("/clients/"):
                rel = path[len("/clients/") :]
                try:
                    filename = safe_name(rel)
                except ValueError:
                    self.send_error(400, "Invalid client name")
                    return
                file_path = clients / filename
                if not file_path.is_file():
                    self.send_error(404, "Client not found")
                    return
                data = file_path.read_bytes()
                ctype = "text/x-sh" if filename.endswith(".sh") else "text/plain"
                self.send_response(200)
                self.send_header("Content-Type", ctype)
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)
                return

            if path.startswith("/files/"):
                rel = path[len("/files/") :]
                try:
                    filename = safe_name(rel)
                except ValueError:
                    self.send_error(400, "Invalid file name")
                    return
                file_path = storage / filename
                if not file_path.is_file():
                    self.send_error(404, "File not found")
                    return
                data = file_path.read_bytes()
                self.send_response(200)
                self.send_header("Content-Type", "application/octet-stream")
                self.send_header("Content-Length", str(len(data)))
                self.send_header(
                    "Content-Disposition", f'attachment; filename="{filename}"'
                )
                self.end_headers()
                self.wfile.write(data)
                return

            self.send_response(200)
            body = b"SFT host. Use /clients/*, POST /send?name=, GET /files/<name>.\n"
            self.send_header("Content-Type", "text/plain")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_POST(self):
            parsed = urlparse(self.path)
            if parsed.path != "/send":
                self.send_error(404)
                return
            qs = parse_qs(parsed.query)
            names = qs.get("name") or []
            if not names:
                self.send_error(400, "Missing name query param")
                return
            try:
                filename = safe_name(names[0])
            except ValueError:
                self.send_error(400, "Invalid file name")
                return
            length = int(self.headers.get("Content-Length", "0"))
            data = self.rfile.read(length)
            dest = storage / filename
            dest.write_bytes(data)
            body = f"stored {filename} ({len(data)} bytes)\n".encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

    return ThreadingHTTPServer((host, port), Handler)


def main():
    parser = argparse.ArgumentParser(description="SFT host server")
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT)
    args = parser.parse_args()
    httpd = make_server(args.host, args.port)
    print(f"Serving HTTP on {args.host}:{args.port} ...", flush=True)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        httpd.server_close()


if __name__ == "__main__":
    main()

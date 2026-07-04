#!/usr/bin/env python3
"""Bridge ESP32 TCP sensor stream into the Octocare Clinic backend for web clients."""

from __future__ import annotations

import argparse
import http.client
import json
import socket
import sys
import time
from urllib.parse import urlparse


def _normalize_line(line: str) -> str:
    text = line.strip()
    if text.upper().startswith("RECEIVED:"):
        text = text.split(":", 1)[1].strip()
    return text


class BackendPoster:
    def __init__(self, backend: str) -> None:
        parsed = urlparse(backend.rstrip("/"))
        if parsed.scheme not in ("http", "https"):
            raise ValueError("Backend URL must start with http:// or https://")
        self._host = parsed.hostname or "127.0.0.1"
        self._port = parsed.port or (443 if parsed.scheme == "https" else 80)
        self._use_ssl = parsed.scheme == "https"
        self._batch_path = "/sensors/live/ingest/batch"
        self._conn: http.client.HTTPConnection | http.client.HTTPSConnection | None = None

    def _ensure_connection(self) -> http.client.HTTPConnection | http.client.HTTPSConnection:
        if self._conn is not None:
            return self._conn
        if self._use_ssl:
            self._conn = http.client.HTTPSConnection(self._host, self._port, timeout=3)
        else:
            self._conn = http.client.HTTPConnection(self._host, self._port, timeout=3)
        return self._conn

    def close(self) -> None:
        if self._conn is not None:
            try:
                self._conn.close()
            except Exception:
                pass
            self._conn = None

    def post_batch(self, lines: list[str]) -> None:
        if not lines:
            return
        body = json.dumps({"lines": lines}).encode("utf-8")
        headers = {
            "Content-Type": "application/json",
            "Connection": "keep-alive",
        }
        for attempt in range(2):
            try:
                conn = self._ensure_connection()
                conn.request("POST", self._batch_path, body=body, headers=headers)
                response = conn.getresponse()
                response.read()
                if response.status >= 400:
                    raise ConnectionError(f"Backend returned HTTP {response.status}")
                return
            except Exception:
                self.close()
                if attempt == 1:
                    raise


def _log(message: str) -> None:
    """Print safely on Windows consoles that lack Unicode support."""
    try:
        print(message)
    except UnicodeEncodeError:
        print(message.encode("ascii", errors="replace").decode("ascii"))


def _flush_pending(poster: BackendPoster, pending: list[str]) -> None:
    if not pending:
        return
    batch = pending[:]
    pending.clear()
    poster.post_batch(batch)
    _log(f">> {len(batch)} lines | last: {batch[-1][:90]}")


def bridge(host: str, port: int, backend: str, flush_ms: int = 20) -> None:
    poster = BackendPoster(backend)
    pending: list[str] = []
    _log(f"Connecting to ESP32 at {host}:{port} ...")
    while True:
        try:
            sock = socket.create_connection((host, port), timeout=10)
            sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            sock.settimeout(0.05)
            _log(f"Connected. Forwarding to {backend} (batch every {flush_ms}ms)")
            buffer = ""
            last_flush = time.monotonic()
            while True:
                timed_out = False
                try:
                    chunk = sock.recv(8192)
                except TimeoutError:
                    timed_out = True
                    chunk = b""

                if chunk:
                    buffer += chunk.decode("utf-8", errors="replace")
                    while "\n" in buffer:
                        line, buffer = buffer.split("\n", 1)
                        normalized = _normalize_line(line)
                        if normalized:
                            pending.append(normalized)
                elif not timed_out:
                    raise ConnectionError("ESP32 closed the connection")

                now = time.monotonic()
                if pending and (now - last_flush) * 1000 >= flush_ms:
                    try:
                        _flush_pending(poster, pending)
                    except Exception as exc:
                        print(f"Backend POST failed: {exc}", file=sys.stderr)
                    last_flush = now
        except Exception as exc:
            try:
                _flush_pending(poster, pending)
            except Exception:
                pass
            print(f"Reconnecting in 1s ({exc})", file=sys.stderr)
            time.sleep(1)


def main() -> None:
    parser = argparse.ArgumentParser(description="ESP32 TCP → backend live sensor bridge")
    parser.add_argument("--esp32", required=True, help="ESP32 IP address")
    parser.add_argument("--port", type=int, default=5000, help="ESP32 TCP port")
    parser.add_argument("--backend", default="http://127.0.0.1:8000", help="Backend base URL")
    parser.add_argument("--flush-ms", type=int, default=20, help="Batch flush interval in ms")
    args = parser.parse_args()
    bridge(args.esp32, args.port, args.backend, flush_ms=max(10, args.flush_ms))


if __name__ == "__main__":
    main()

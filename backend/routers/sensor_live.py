import asyncio
from collections import deque
from typing import Set

from fastapi import APIRouter, Body, Query, WebSocket, WebSocketDisconnect

router = APIRouter()

_live_clients: Set[WebSocket] = set()
_latest_line: str = ""
_line_seq: int = 0
_recent_lines: deque[tuple[int, str]] = deque(maxlen=800)


async def _broadcast(line: str) -> None:
    if not _live_clients:
        return
    stale: list[WebSocket] = []
    for ws in list(_live_clients):
        try:
            await ws.send_text(line)
        except Exception:
            stale.append(ws)
    for ws in stale:
        _live_clients.discard(ws)


async def _ingest_lines(lines: list[str]) -> int:
    global _latest_line, _line_seq
    sent = 0
    for line in lines:
        text = line.strip()
        if not text:
            continue
        _line_seq += 1
        _latest_line = text
        _recent_lines.append((_line_seq, text))
        await _broadcast(text)
        sent += 1
    return sent


@router.websocket("/live/ws")
async def live_sensor_websocket(websocket: WebSocket):
    await websocket.accept()
    _live_clients.add(websocket)
    try:
        if _latest_line:
            await websocket.send_text(_latest_line)
        while True:
            await websocket.receive_text()
    except WebSocketDisconnect:
        pass
    finally:
        _live_clients.discard(websocket)


@router.post("/live/ingest")
async def ingest_live_sensor_line(payload: dict = Body(...)):
    line = str(payload.get("line", "")).strip()
    if not line:
        return {"ok": False, "detail": "line is required"}

    sent = await _ingest_lines([line])
    return {"ok": True, "clients": len(_live_clients), "sent": sent, "seq": _line_seq}


@router.post("/live/ingest/batch")
async def ingest_live_sensor_batch(payload: dict = Body(...)):
    raw_lines = payload.get("lines")
    if not isinstance(raw_lines, list) or not raw_lines:
        return {"ok": False, "detail": "lines array is required"}

    sent = await _ingest_lines([str(line) for line in raw_lines])
    return {"ok": True, "clients": len(_live_clients), "sent": sent, "seq": _line_seq}


@router.get("/live/latest")
def live_sensor_latest():
    return {
        "line": _latest_line,
        "has_data": bool(_latest_line),
        "seq": _line_seq,
    }


@router.get("/live/recent")
def live_sensor_recent(
    since: int = Query(0, ge=0),
    limit: int = Query(200, ge=1, le=400),
):
    items = [(seq, line) for seq, line in _recent_lines if seq > since]
    if len(items) > limit:
        items = items[-limit:]
    return {
        "lines": [line for _, line in items],
        "seq": _line_seq,
        "latest": _latest_line,
        "has_data": bool(_latest_line),
    }


@router.get("/live/status")
def live_sensor_status():
    return {
        "clients": len(_live_clients),
        "has_latest": bool(_latest_line),
        "latest_preview": _latest_line[:120] if _latest_line else "",
        "seq": _line_seq,
        "buffered": len(_recent_lines),
    }

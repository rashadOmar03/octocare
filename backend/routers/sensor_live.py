import asyncio
from typing import Set

from fastapi import APIRouter, Body, WebSocket, WebSocketDisconnect

router = APIRouter()

_live_clients: Set[WebSocket] = set()
_latest_line: str = ""


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
    global _latest_line
    sent = 0
    for line in lines:
        text = line.strip()
        if not text:
            continue
        _latest_line = text
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
    return {"ok": True, "clients": len(_live_clients), "sent": sent}


@router.post("/live/ingest/batch")
async def ingest_live_sensor_batch(payload: dict = Body(...)):
    raw_lines = payload.get("lines")
    if not isinstance(raw_lines, list) or not raw_lines:
        return {"ok": False, "detail": "lines array is required"}

    sent = await _ingest_lines([str(line) for line in raw_lines])
    return {"ok": True, "clients": len(_live_clients), "sent": sent}


@router.get("/live/status")
def live_sensor_status():
    return {
        "clients": len(_live_clients),
        "has_latest": bool(_latest_line),
        "latest_preview": _latest_line[:120] if _latest_line else "",
    }

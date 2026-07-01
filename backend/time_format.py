from datetime import datetime


def format_time_12h(time_24: str | None) -> str:
    """Convert 24h HH:mm to 12h e.g. 2:30 PM."""
    if not time_24 or ":" not in time_24:
        return time_24 or "-"
    parts = time_24.split(":")
    try:
        h, m = int(parts[0]), int(parts[1])
    except ValueError:
        return time_24
    dt = datetime(2000, 1, 1, h, m)
    return dt.strftime("%I:%M %p").lstrip("0")

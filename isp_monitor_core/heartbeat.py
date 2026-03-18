import ipaddress
import json
import re
import time
from dataclasses import asdict, dataclass
from typing import Any, Mapping


DEFAULT_DEVICE_NAME = "unknown"
DEFAULT_NOTE = ""
DEFAULT_IP_ADDRESS = "unknown"
MAX_DEVICE_LENGTH = 100
MAX_NOTE_LENGTH = 500
CONTROL_CHARACTER_PATTERN = re.compile(r"[\x00-\x1f\x7f-\x9f]")


@dataclass(frozen=True)
class HeartbeatInput:
    device: str
    note: str
    ip: str


@dataclass(frozen=True)
class HeartbeatLog:
    ts: int
    device: str
    ip: str
    note: str


def sanitize_string(value: Any, max_length: int, default: str = "") -> str:
    """Remove control characters, trim whitespace, and enforce max length."""
    if value is None:
        return default

    sanitized = CONTROL_CHARACTER_PATTERN.sub("", str(value)).strip()
    if not sanitized:
        return default

    return sanitized[:max_length]


def validate_ip(ip_value: Any) -> str:
    """Return the first valid IP address from a header-like value."""
    if ip_value is None:
        return DEFAULT_IP_ADDRESS

    ip_candidate = str(ip_value).split(",")[0].strip()
    if not ip_candidate:
        return DEFAULT_IP_ADDRESS

    try:
        return str(ipaddress.ip_address(ip_candidate))
    except ValueError:
        return DEFAULT_IP_ADDRESS


def extract_heartbeat_input(
    body: Any,
    *,
    device_header: Any = None,
    ip_header: Any = None,
) -> HeartbeatInput:
    body_data = _parse_body(body)

    device = sanitize_string(
        body_data.get("device") or device_header,
        MAX_DEVICE_LENGTH,
        DEFAULT_DEVICE_NAME,
    )
    note = sanitize_string(
        body_data.get("note"),
        MAX_NOTE_LENGTH,
        DEFAULT_NOTE,
    )
    ip = validate_ip(ip_header)

    return HeartbeatInput(device=device, note=note, ip=ip)


def build_log_entry(heartbeat_input: HeartbeatInput, *, now: int | None = None) -> HeartbeatLog:
    return HeartbeatLog(
        ts=int(time.time() if now is None else now),
        device=heartbeat_input.device,
        ip=heartbeat_input.ip,
        note=heartbeat_input.note,
    )


def format_log_line(log_entry: HeartbeatLog) -> str:
    return f"[heartbeat] {json.dumps(asdict(log_entry))}"


def _parse_body(body: Any) -> dict[str, Any]:
    if body is None or body == "":
        return {}

    if isinstance(body, Mapping):
        return dict(body)

    if isinstance(body, bytes):
        try:
            body = body.decode("utf-8")
        except UnicodeDecodeError:
            return {}

    if isinstance(body, str):
        try:
            parsed = json.loads(body)
        except json.JSONDecodeError:
            return {}

        if isinstance(parsed, Mapping):
            return dict(parsed)

    return {}

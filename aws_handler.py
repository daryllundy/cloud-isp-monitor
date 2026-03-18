import base64
from typing import Any

from isp_monitor_core import (
    build_log_entry,
    extract_heartbeat_input,
    format_log_line,
    sanitize_string,
    validate_ip,
)


def lambda_handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    headers = event.get("headers") or {}
    heartbeat_input = extract_heartbeat_input(
        _extract_body(event),
        device_header=_first_header(headers, "x-device"),
        ip_header=_first_header(headers, "x-forwarded-for"),
    )

    print(format_log_line(build_log_entry(heartbeat_input)))

    return {
        "statusCode": 200,
        "headers": {
            "Content-Type": "text/plain",
        },
        "body": "ok",
    }


def _extract_body(event: dict[str, Any]) -> Any:
    body = event.get("body")
    if not body:
        return body

    if event.get("isBase64Encoded"):
        try:
            return base64.b64decode(body)
        except (ValueError, TypeError):
            return None

    return body


def _first_header(headers: dict[str, Any], header_name: str) -> Any:
    return headers.get(header_name) or headers.get(header_name.title())

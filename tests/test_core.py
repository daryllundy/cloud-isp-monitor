import json

from isp_monitor_core import (
    DEFAULT_DEVICE_NAME,
    DEFAULT_IP_ADDRESS,
    DEFAULT_NOTE,
    MAX_DEVICE_LENGTH,
    MAX_NOTE_LENGTH,
    HeartbeatInput,
    build_log_entry,
    extract_heartbeat_input,
    format_log_line,
    sanitize_string,
    validate_ip,
)


def test_sanitize_string_strips_control_characters_and_truncates():
    value = "  hello\x00world\n" + ("x" * 200)
    result = sanitize_string(value, max_length=10, default="fallback")
    assert result == "helloworld"


def test_sanitize_string_uses_default_for_empty_values():
    assert sanitize_string(None, max_length=10, default="fallback") == "fallback"
    assert sanitize_string(" \n\t ", max_length=10, default="fallback") == "fallback"


def test_validate_ip_supports_ipv4_and_ipv6_and_rejects_invalid():
    assert validate_ip("203.0.113.5") == "203.0.113.5"
    assert validate_ip("2001:db8::1") == "2001:db8::1"
    assert validate_ip("999.1.1.1") == DEFAULT_IP_ADDRESS


def test_validate_ip_uses_first_forwarded_address():
    assert validate_ip("203.0.113.10, 10.0.0.1") == "203.0.113.10"


def test_extract_heartbeat_input_prefers_body_fields():
    heartbeat = extract_heartbeat_input(
        {"device": "body-device", "note": "body-note"},
        device_header="header-device",
        ip_header="203.0.113.11",
    )
    assert heartbeat == HeartbeatInput(
        device="body-device",
        note="body-note",
        ip="203.0.113.11",
    )


def test_extract_heartbeat_input_falls_back_to_headers_and_defaults():
    heartbeat = extract_heartbeat_input(
        '{"note": ""}',
        device_header=" header-device ",
        ip_header="not-an-ip",
    )
    assert heartbeat.device == "header-device"
    assert heartbeat.note == DEFAULT_NOTE
    assert heartbeat.ip == DEFAULT_IP_ADDRESS


def test_extract_heartbeat_input_handles_bytes_and_length_limits():
    heartbeat = extract_heartbeat_input(
        json.dumps(
            {
                "device": "x" * (MAX_DEVICE_LENGTH + 10),
                "note": "y" * (MAX_NOTE_LENGTH + 10),
            }
        ).encode("utf-8"),
        ip_header="2001:db8::42",
    )
    assert len(heartbeat.device) == MAX_DEVICE_LENGTH
    assert len(heartbeat.note) == MAX_NOTE_LENGTH
    assert heartbeat.ip == "2001:db8::42"


def test_extract_heartbeat_input_uses_unknown_device_when_missing():
    heartbeat = extract_heartbeat_input({}, ip_header=None)
    assert heartbeat.device == DEFAULT_DEVICE_NAME
    assert heartbeat.note == DEFAULT_NOTE
    assert heartbeat.ip == DEFAULT_IP_ADDRESS


def test_log_entry_and_format_are_stable():
    log_entry = build_log_entry(
        HeartbeatInput(device="device-a", note="hello", ip="203.0.113.4"),
        now=1234567890,
    )
    assert log_entry.ts == 1234567890
    assert json.loads(format_log_line(log_entry).replace("[heartbeat] ", "")) == {
        "ts": 1234567890,
        "device": "device-a",
        "ip": "203.0.113.4",
        "note": "hello",
    }

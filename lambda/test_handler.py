"""
Property-based and unit tests for Lambda handler.

Uses hypothesis for property-based testing to verify correctness properties
across a wide range of inputs.
"""

import json
import re
from hypothesis import given, strategies as st, settings
from handler import sanitize_string, validate_ip


# Feature: aws-migration, Property 1: Device name sanitization and length constraint
@given(st.text(min_size=0, max_size=200))
@settings(max_examples=100)
def test_property_device_name_sanitization(input_string):
    """
    Property 1: Device name sanitization and length constraint
    
    For any input string, the sanitized device name should:
    - Contain no control characters (0x00-0x1f, 0x7f-0x9f)
    - Not exceed 100 characters in length
    
    Validates: Requirements 2.2
    """
    result = sanitize_string(input_string, max_length=100, default="unknown")
    
    # Verify no control characters in output
    control_chars = re.compile(r'[\x00-\x1f\x7f-\x9f]')
    assert not control_chars.search(result), f"Output contains control characters: {repr(result)}"
    
    # Verify length constraint
    assert len(result) <= 100, f"Output exceeds 100 characters: {len(result)}"



# Feature: aws-migration, Property 2: Note sanitization and length constraint
@given(st.text(min_size=0, max_size=1000))
@settings(max_examples=100)
def test_property_note_sanitization(input_string):
    """
    Property 2: Note sanitization and length constraint
    
    For any input string, the sanitized note should:
    - Contain no control characters (0x00-0x1f, 0x7f-0x9f)
    - Not exceed 500 characters in length
    
    Validates: Requirements 2.3
    """
    result = sanitize_string(input_string, max_length=500, default="")
    
    # Verify no control characters in output
    control_chars = re.compile(r'[\x00-\x1f\x7f-\x9f]')
    assert not control_chars.search(result), f"Output contains control characters: {repr(result)}"
    
    # Verify length constraint
    assert len(result) <= 500, f"Output exceeds 500 characters: {len(result)}"



# Feature: aws-migration, Property 3: IP address validation
@given(st.one_of(
    st.text(min_size=0, max_size=100),  # Random strings
    st.from_regex(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$', fullmatch=True),  # IPv4-like
    st.from_regex(r'^[0-9a-fA-F:]+$', fullmatch=True),  # IPv6-like
))
@settings(max_examples=100)
def test_property_ip_validation(input_string):
    """
    Property 3: IP address validation
    
    For any input string, the validated IP should be either:
    - A valid IPv4 address (0-255.0-255.0-255.0-255)
    - A valid IPv6 address (hex groups separated by colons)
    - The string "unknown"
    
    Validates: Requirements 2.4
    """
    result = validate_ip(input_string)
    
    # Result must be either "unknown" or a valid IP format
    if result == "unknown":
        # This is acceptable
        pass
    else:
        # Check if it's a valid IPv4
        ipv4_pattern = r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$'
        ipv4_match = re.match(ipv4_pattern, result)
        
        # Check if it's a valid IPv6
        ipv6_pattern = r'^[0-9a-fA-F:]+$'
        ipv6_match = re.match(ipv6_pattern, result)
        
        assert ipv4_match or ipv6_match, f"Output is neither valid IP nor 'unknown': {result}"
        
        # If IPv4, verify octets are in range
        if ipv4_match:
            octets = [int(g) for g in ipv4_match.groups()]
            assert all(0 <= octet <= 255 for octet in octets), f"IPv4 octets out of range: {result}"



# Feature: aws-migration, Property 4: Structured logging format
@given(
    device=st.text(min_size=0, max_size=100),
    note=st.text(min_size=0, max_size=500),
    ip=st.one_of(
        st.from_regex(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$', fullmatch=True),
        st.just("unknown")
    )
)
@settings(max_examples=100)
def test_property_structured_logging(device, note, ip):
    """
    Property 4: Structured logging format
    
    For any valid request, the logged output should be valid JSON containing
    the required fields: ts, device, ip, and note.
    
    Validates: Requirements 2.5
    """
    import sys
    from io import StringIO
    from handler import lambda_handler
    
    # Create a valid Lambda Function URL event
    event = {
        "version": "2.0",
        "routeKey": "$default",
        "rawPath": "/",
        "headers": {
            "x-forwarded-for": ip,
            "content-type": "application/json"
        },
        "body": json.dumps({"device": device, "note": note}),
        "isBase64Encoded": False
    }
    
    # Capture stdout
    old_stdout = sys.stdout
    sys.stdout = captured_output = StringIO()
    
    try:
        # Call handler
        response = lambda_handler(event, None)
        
        # Get captured output
        log_line = captured_output.getvalue().strip()
    finally:
        sys.stdout = old_stdout
    
    # Extract the JSON from the log line
    assert log_line.startswith("[heartbeat]"), f"Log line doesn't start with [heartbeat]: {log_line}"
    
    json_str = log_line.replace("[heartbeat] ", "")
    
    # Verify it's valid JSON
    try:
        log_data = json.loads(json_str)
    except json.JSONDecodeError as e:
        assert False, f"Log output is not valid JSON: {json_str}, error: {e}"
    
    # Verify required fields exist
    assert "ts" in log_data, "Missing 'ts' field in log output"
    assert "device" in log_data, "Missing 'device' field in log output"
    assert "ip" in log_data, "Missing 'ip' field in log output"
    assert "note" in log_data, "Missing 'note' field in log output"
    
    # Verify ts is an integer (Unix timestamp)
    assert isinstance(log_data["ts"], int), f"'ts' field is not an integer: {type(log_data['ts'])}"



# Feature: aws-migration, Property 5: Successful response format
@given(
    device=st.text(min_size=0, max_size=100),
    note=st.text(min_size=0, max_size=500),
    method=st.sampled_from(["GET", "POST"])
)
@settings(max_examples=100)
def test_property_response_format(device, note, method):
    """
    Property 5: Successful response format
    
    For any valid request, the Lambda function should return:
    - HTTP 200 status code
    - Body "ok"
    - Content-Type "text/plain"
    
    Validates: Requirements 2.6
    """
    import sys
    from io import StringIO
    from handler import lambda_handler
    
    # Create a valid Lambda Function URL event
    event = {
        "version": "2.0",
        "routeKey": "$default",
        "rawPath": "/",
        "requestContext": {
            "http": {
                "method": method
            }
        },
        "headers": {
            "x-forwarded-for": "192.168.1.1",
            "content-type": "application/json"
        },
        "body": json.dumps({"device": device, "note": note}) if method == "POST" else None,
        "isBase64Encoded": False
    }
    
    # Suppress stdout for this test
    old_stdout = sys.stdout
    sys.stdout = StringIO()
    
    try:
        # Call handler
        response = lambda_handler(event, None)
    finally:
        sys.stdout = old_stdout
    
    # Verify response format
    assert "statusCode" in response, "Response missing 'statusCode'"
    assert response["statusCode"] == 200, f"Expected status 200, got {response['statusCode']}"
    
    assert "body" in response, "Response missing 'body'"
    assert response["body"] == "ok", f"Expected body 'ok', got {response['body']}"
    
    assert "headers" in response, "Response missing 'headers'"
    assert "Content-Type" in response["headers"], "Response headers missing 'Content-Type'"
    assert response["headers"]["Content-Type"] == "text/plain", \
        f"Expected Content-Type 'text/plain', got {response['headers']['Content-Type']}"



# Unit tests for specific edge cases
def test_get_method():
    """Test that GET method is accepted."""
    import sys
    from io import StringIO
    from handler import lambda_handler
    
    event = {
        "version": "2.0",
        "routeKey": "$default",
        "rawPath": "/",
        "requestContext": {"http": {"method": "GET"}},
        "headers": {"x-forwarded-for": "192.168.1.1"},
        "body": None,
        "isBase64Encoded": False
    }
    
    old_stdout = sys.stdout
    sys.stdout = StringIO()
    try:
        response = lambda_handler(event, None)
    finally:
        sys.stdout = old_stdout
    
    assert response["statusCode"] == 200
    assert response["body"] == "ok"


def test_post_method():
    """Test that POST method is accepted."""
    import sys
    from io import StringIO
    from handler import lambda_handler
    
    event = {
        "version": "2.0",
        "routeKey": "$default",
        "rawPath": "/",
        "requestContext": {"http": {"method": "POST"}},
        "headers": {
            "x-forwarded-for": "192.168.1.1",
            "content-type": "application/json"
        },
        "body": json.dumps({"device": "test-device", "note": "test note"}),
        "isBase64Encoded": False
    }
    
    old_stdout = sys.stdout
    sys.stdout = StringIO()
    try:
        response = lambda_handler(event, None)
    finally:
        sys.stdout = old_stdout
    
    assert response["statusCode"] == 200
    assert response["body"] == "ok"


def test_empty_inputs_use_defaults():
    """Test that empty/missing inputs use default values."""
    import sys
    from io import StringIO
    from handler import lambda_handler
    
    event = {
        "version": "2.0",
        "routeKey": "$default",
        "rawPath": "/",
        "headers": {},
        "body": json.dumps({}),
        "isBase64Encoded": False
    }
    
    old_stdout = sys.stdout
    sys.stdout = captured = StringIO()
    try:
        response = lambda_handler(event, None)
        log_output = captured.getvalue()
    finally:
        sys.stdout = old_stdout
    
    # Verify defaults are used
    assert "unknown" in log_output  # Default device or IP
    assert response["statusCode"] == 200


def test_oversized_inputs_truncated():
    """Test that oversized inputs are truncated to max length."""
    import sys
    from io import StringIO
    from handler import lambda_handler
    
    # Create oversized inputs
    long_device = "x" * 200  # 200 chars, should be truncated to 100
    long_note = "y" * 1000   # 1000 chars, should be truncated to 500
    
    event = {
        "version": "2.0",
        "routeKey": "$default",
        "rawPath": "/",
        "headers": {"x-forwarded-for": "192.168.1.1"},
        "body": json.dumps({"device": long_device, "note": long_note}),
        "isBase64Encoded": False
    }
    
    old_stdout = sys.stdout
    sys.stdout = captured = StringIO()
    try:
        response = lambda_handler(event, None)
        log_output = captured.getvalue()
    finally:
        sys.stdout = old_stdout
    
    # Parse the log output
    json_str = log_output.strip().replace("[heartbeat] ", "")
    log_data = json.loads(json_str)
    
    # Verify truncation
    assert len(log_data["device"]) <= 100, f"Device not truncated: {len(log_data['device'])}"
    assert len(log_data["note"]) <= 500, f"Note not truncated: {len(log_data['note'])}"
    assert response["statusCode"] == 200


def test_invalid_json_handled_gracefully():
    """Test that invalid JSON body is handled gracefully."""
    import sys
    from io import StringIO
    from handler import lambda_handler
    
    event = {
        "version": "2.0",
        "routeKey": "$default",
        "rawPath": "/",
        "headers": {"x-forwarded-for": "192.168.1.1"},
        "body": "not valid json {{{",
        "isBase64Encoded": False
    }
    
    old_stdout = sys.stdout
    sys.stdout = StringIO()
    try:
        response = lambda_handler(event, None)
    finally:
        sys.stdout = old_stdout
    
    # Should still return 200 with defaults
    assert response["statusCode"] == 200
    assert response["body"] == "ok"

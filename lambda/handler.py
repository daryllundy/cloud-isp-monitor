# AWS Lambda handler for ISP Monitor heartbeat endpoint
# This function receives heartbeat pings and logs them to CloudWatch

import json
import time
import re
from typing import Dict, Any, Optional


def sanitize_string(value: Optional[str], max_length: int, default: str = "") -> str:
    """
    Sanitize a string by removing control characters and enforcing length limits.
    
    Args:
        value: Input string to sanitize (can be None)
        max_length: Maximum allowed length
        default: Default value if input is None or empty
    
    Returns:
        Sanitized string with no control characters and length <= max_length
    """
    if value is None or value == "":
        return default
    
    # Remove control characters (0x00-0x1f and 0x7f-0x9f)
    sanitized = re.sub(r'[\x00-\x1f\x7f-\x9f]', '', str(value))
    
    # Enforce maximum length
    if len(sanitized) > max_length:
        sanitized = sanitized[:max_length]
    
    return sanitized


def validate_ip(ip_string: Optional[str]) -> str:
    """
    Validate and extract IP address from string.
    
    Supports IPv4 and IPv6 formats. Returns "unknown" for invalid inputs.
    
    Args:
        ip_string: IP address string to validate
    
    Returns:
        Valid IP address or "unknown"
    """
    if ip_string is None or ip_string == "":
        return "unknown"
    
    # Take first IP if multiple (X-Forwarded-For can have multiple IPs)
    ip = ip_string.split(',')[0].strip()
    
    # IPv4 pattern: 0-255.0-255.0-255.0-255
    ipv4_pattern = r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$'
    ipv4_match = re.match(ipv4_pattern, ip)
    
    if ipv4_match:
        # Validate each octet is 0-255
        octets = [int(g) for g in ipv4_match.groups()]
        if all(0 <= octet <= 255 for octet in octets):
            return ip
    
    # IPv6 pattern: simplified check for hex groups separated by colons
    ipv6_pattern = r'^([0-9a-fA-F]{0,4}:){2,7}[0-9a-fA-F]{0,4}$'
    if re.match(ipv6_pattern, ip):
        return ip
    
    # Also accept IPv6 with :: compression
    if '::' in ip:
        parts = ip.split('::')
        if len(parts) == 2:
            # Basic validation - should have hex groups
            if all(re.match(r'^([0-9a-fA-F]{0,4}:)*[0-9a-fA-F]{0,4}$', part) or part == '' for part in parts):
                return ip
    
    return "unknown"


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda handler for heartbeat pings.
    
    Accepts GET and POST requests, validates input, and logs structured data.
    
    Args:
        event: Lambda Function URL event (version 2.0)
        context: Lambda context object
    
    Returns:
        HTTP response with status 200 and "ok" body
    """
    # Extract device name from body or headers
    device = "unknown"
    note = ""
    
    # Try to parse JSON body
    body = event.get('body', '')
    if body:
        try:
            body_data = json.loads(body)
            device = body_data.get('device', device)
            note = body_data.get('note', note)
        except (json.JSONDecodeError, AttributeError):
            # Invalid JSON - use defaults
            pass
    
    # Fallback to X-Device header if body didn't provide device
    if device == "unknown":
        headers = event.get('headers', {})
        device = headers.get('x-device', headers.get('X-Device', 'unknown'))
    
    # Extract IP from X-Forwarded-For header
    headers = event.get('headers', {})
    ip_string = headers.get('x-forwarded-for', headers.get('X-Forwarded-For', None))
    
    # Sanitize and validate inputs
    device = sanitize_string(device, max_length=100, default="unknown")
    note = sanitize_string(note, max_length=500, default="")
    ip = validate_ip(ip_string)
    
    # Create structured log entry
    log_entry = {
        "ts": int(time.time()),
        "device": device,
        "ip": ip,
        "note": note
    }
    
    # Log to CloudWatch (print outputs to CloudWatch Logs)
    print(f"[heartbeat] {json.dumps(log_entry)}")
    
    # Return HTTP 200 response
    return {
        "statusCode": 200,
        "headers": {
            "Content-Type": "text/plain"
        },
        "body": "ok"
    }

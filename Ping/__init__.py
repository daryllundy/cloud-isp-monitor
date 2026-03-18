import azure.functions as func
from isp_monitor_core import build_log_entry, extract_heartbeat_input, format_log_line

def main(req: func.HttpRequest) -> func.HttpResponse:
    heartbeat_input = extract_heartbeat_input(
        req.get_body(),
        device_header=req.headers.get("X-Device") or req.headers.get("x-device"),
        ip_header=req.headers.get("X-Forwarded-For") or req.headers.get("X-Client-IP"),
    )

    print(format_log_line(build_log_entry(heartbeat_input)))

    return func.HttpResponse("ok", status_code=200, headers={"Content-Type":"text/plain"})

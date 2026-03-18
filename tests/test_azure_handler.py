import json

import Ping


class FakeRequest:
    def __init__(self, body=b"", headers=None):
        self._body = body
        self.headers = headers or {}

    def get_body(self):
        return self._body


def test_azure_handler_uses_shared_core_defaults(capsys):
    response = Ping.main(FakeRequest())
    captured = capsys.readouterr()

    assert response.status_code == 200
    assert response.get_body().decode("utf-8") == "ok"

    payload = json.loads(captured.out.strip().replace("[heartbeat] ", ""))
    assert payload["device"] == "unknown"
    assert payload["ip"] == "unknown"
    assert payload["note"] == ""


def test_azure_handler_prefers_body_fields_and_validates_ip(capsys):
    request = FakeRequest(
        body=json.dumps({"device": "body-device", "note": "body-note"}).encode("utf-8"),
        headers={
            "X-Device": "header-device",
            "X-Forwarded-For": "999.1.1.1",
        },
    )

    response = Ping.main(request)
    captured = capsys.readouterr()

    assert response.status_code == 200
    payload = json.loads(captured.out.strip().replace("[heartbeat] ", ""))
    assert payload["device"] == "body-device"
    assert payload["note"] == "body-note"
    assert payload["ip"] == "unknown"

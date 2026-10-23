import requests

import app as frontend


class FakeResponse:
    def __init__(self, payload, status=200):
        self.payload = payload
        self.status = status

    def raise_for_status(self):
        if self.status >= 400:
            raise requests.HTTPError(f"status {self.status}")

    def json(self):
        return self.payload


class FakeSession:
    def __init__(self, response=None, error=None):
        self.response = response
        self.error = error

    def get(self, url, timeout):
        if self.error:
            raise self.error
        return self.response


def page_requests():
    return frontend.REQUESTS.labels(method="GET", path="/", status="200")._value.get()


def setup_function():
    frontend.state.update(value=None, updated=None)
    frontend.app.config.update(TESTING=True)


def test_index_shows_version_and_value(monkeypatch):
    monkeypatch.setattr(frontend, "APP_VERSION", "v1.0.0")
    frontend.poll_once(FakeSession(FakeResponse({"value": 42})))
    body = frontend.app.test_client().get("/").get_data(as_text=True)
    assert body == "Hello Lab-Commit v1.0.0 42\n"


def test_index_before_first_poll(monkeypatch):
    monkeypatch.setattr(frontend, "APP_VERSION", "v1.0.0")
    body = frontend.app.test_client().get("/").get_data(as_text=True)
    assert body == "Hello Lab-Commit v1.0.0 n/a\n"


def test_index_marks_stale_value(monkeypatch):
    monkeypatch.setattr(frontend, "APP_VERSION", "v1.0.0")
    frontend.state.update(value=42, updated=frontend.time.time() - frontend.STALE_SECONDS - 1)
    body = frontend.app.test_client().get("/").get_data(as_text=True)
    assert body == "Hello Lab-Commit v1.0.0 42 (stale)\n"


def test_healthz_not_ready_before_first_poll():
    response = frontend.app.test_client().get("/healthz")
    assert response.status_code == 503
    assert response.get_json()["status"] == "stale"


def test_healthz_ready_with_fresh_value():
    frontend.poll_once(FakeSession(FakeResponse({"value": 42})))
    response = frontend.app.test_client().get("/healthz")
    assert response.status_code == 200
    assert response.get_json()["value"] == 42


def test_healthz_not_ready_with_stale_value():
    frontend.state.update(value=42, updated=frontend.time.time() - frontend.STALE_SECONDS - 1)
    assert frontend.app.test_client().get("/healthz").status_code == 503


def test_livez_ignores_backend_state():
    assert frontend.app.test_client().get("/livez").status_code == 200


def test_poll_failure_keeps_last_value():
    frontend.poll_once(FakeSession(FakeResponse({"value": 7})))
    frontend.poll_once(FakeSession(error=requests.ConnectionError("down")))
    frontend.poll_once(FakeSession(FakeResponse({}, status=503)))
    assert frontend.state["value"] == 7


def test_only_page_requests_are_counted():
    client = frontend.app.test_client()
    before = page_requests()
    client.get("/")
    client.get("/healthz")
    client.get("/livez")
    client.get("/metrics")
    client.get("/")
    assert page_requests() - before == 2


def test_metrics_exposes_http_requests_total():
    client = frontend.app.test_client()
    client.get("/")
    body = client.get("/metrics").get_data(as_text=True)
    assert 'http_requests_total{method="GET",path="/",status="200"}' in body

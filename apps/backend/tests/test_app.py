import psycopg
import pytest

import app as backend
import seed


class FakeResult:
    def __init__(self, row):
        self.row = row

    def fetchone(self):
        return self.row


class FakeCursor:
    def __init__(self, conn):
        self.conn = conn

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False

    def executemany(self, sql, rows):
        self.conn.inserted.extend(rows)


class FakeConn:
    def __init__(self, rows=None, count=0):
        self.rows = list(rows or [])
        self.count = count
        self.executed = []
        self.inserted = []

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False

    def execute(self, sql):
        self.executed.append(sql)
        if "count(*) FROM lab_values" in sql and "nextval" not in sql:
            return FakeResult((self.count,))
        return FakeResult(self.rows.pop(0) if self.rows else None)

    def cursor(self):
        return FakeCursor(self)


@pytest.fixture
def client():
    backend.app.config.update(TESTING=True)
    return backend.app.test_client()


def test_healthz(client):
    assert client.get("/healthz").get_json() == {"status": "ok"}


def test_value_rotates(client, monkeypatch):
    conns = iter([FakeConn([(7,)]), FakeConn([(13,)])])
    monkeypatch.setattr(backend, "connect", lambda force_refresh=False: next(conns))
    assert client.get("/value").get_json() == {"value": 7}
    assert client.get("/value").get_json() == {"value": 13}


def test_value_empty_table(client, monkeypatch):
    monkeypatch.setattr(backend, "connect", lambda force_refresh=False: FakeConn([]))
    response = client.get("/value")
    assert response.status_code == 503


def test_value_retries_with_fresh_secret(client, monkeypatch):
    calls = []

    def fake_connect(force_refresh=False):
        calls.append(force_refresh)
        if not force_refresh:
            raise psycopg.OperationalError("password authentication failed")
        return FakeConn([(42,)])

    monkeypatch.setattr(backend, "connect", fake_connect)
    assert client.get("/value").get_json() == {"value": 42}
    assert calls == [False, True]


def test_seed_inserts_when_empty(monkeypatch):
    conn = FakeConn(count=0)
    monkeypatch.setattr(seed, "connect", lambda: conn)
    monkeypatch.setenv("SEED_VALUES", "1,2,3")
    seed.main()
    assert conn.inserted == [(1,), (2,), (3,)]


def test_seed_is_idempotent(monkeypatch):
    conn = FakeConn(count=6)
    monkeypatch.setattr(seed, "connect", lambda: conn)
    seed.main()
    assert conn.inserted == []

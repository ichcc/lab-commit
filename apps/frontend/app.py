import os
import threading
import time

import requests
from flask import Flask, Response
from prometheus_client import CONTENT_TYPE_LATEST, Counter, generate_latest

APP_VERSION = os.environ.get("APP_VERSION", "dev")
BACKEND_URL = os.environ.get("BACKEND_URL", "http://backend:8000")
POLL_SECONDS = float(os.environ.get("POLL_SECONDS", "5"))

REQUESTS = Counter("http_requests", "Page requests served", ["method", "path", "status"])

app = Flask(__name__)
state = {"value": None, "updated": None}
_poller = {"thread": None}


def poll_once(session):
    try:
        response = session.get(f"{BACKEND_URL}/value", timeout=3)
        response.raise_for_status()
        state["value"] = response.json()["value"]
        state["updated"] = time.time()
    except (requests.RequestException, KeyError, ValueError) as exc:
        app.logger.warning("backend poll failed: %s", exc)


def poll_forever():
    session = requests.Session()
    while True:
        poll_once(session)
        time.sleep(POLL_SECONDS)


def start_poller():
    if _poller["thread"] is None:
        _poller["thread"] = threading.Thread(target=poll_forever, name="backend-poller", daemon=True)
        _poller["thread"].start()


@app.get("/")
def index():
    value = "n/a" if state["value"] is None else state["value"]
    REQUESTS.labels(method="GET", path="/", status="200").inc()
    return Response(f"Hello Lab-Commit {APP_VERSION} {value}\n", mimetype="text/plain")


@app.get("/healthz")
def healthz():
    return {"status": "ok", "version": APP_VERSION, "value": state["value"]}


@app.get("/metrics")
def metrics():
    return Response(generate_latest(), mimetype=CONTENT_TYPE_LATEST)

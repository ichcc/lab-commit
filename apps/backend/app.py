import json
import os
import time

import boto3
import psycopg
from flask import Flask, jsonify

NEXT_VALUE_SQL = """
SELECT value FROM lab_values
ORDER BY id
OFFSET (SELECT (nextval('lab_values_cursor') - 1) % GREATEST(count(*), 1) FROM lab_values)
LIMIT 1
"""

app = Flask(__name__)
_secret = {"value": None, "fetched": 0.0}


def credentials(force=False):
    ttl = float(os.environ.get("SECRET_TTL_SECONDS", "300"))
    if force or _secret["value"] is None or time.time() - _secret["fetched"] > ttl:
        client = boto3.client("secretsmanager")
        payload = client.get_secret_value(SecretId=os.environ["DB_SECRET_ARN"])
        _secret["value"] = json.loads(payload["SecretString"])
        _secret["fetched"] = time.time()
    return _secret["value"]


def connect(force_refresh=False):
    creds = credentials(force_refresh)
    return psycopg.connect(
        host=os.environ["DB_HOST"],
        port=int(os.environ.get("DB_PORT", "5432")),
        dbname=os.environ.get("DB_NAME", "lab"),
        user=creds["username"],
        password=creds["password"],
        sslmode=os.environ.get("DB_SSLMODE", "require"),
        connect_timeout=5,
    )


def next_value():
    try:
        conn = connect()
    except psycopg.OperationalError:
        conn = connect(force_refresh=True)
    with conn:
        row = conn.execute(NEXT_VALUE_SQL).fetchone()
    return None if row is None else row[0]


@app.get("/value")
def value():
    try:
        result = next_value()
    except psycopg.Error as exc:
        app.logger.error("database error: %s", exc)
        return jsonify(error="database unavailable"), 503
    if result is None:
        return jsonify(error="no values"), 503
    return jsonify(value=result)


@app.get("/healthz")
def healthz():
    return jsonify(status="ok")

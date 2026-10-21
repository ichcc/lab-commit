import os

from app import connect

SCHEMA = [
    "CREATE TABLE IF NOT EXISTS lab_values (id serial PRIMARY KEY, value int)",
    "CREATE SEQUENCE IF NOT EXISTS lab_values_cursor",
]


def seed_values():
    raw = os.environ.get("SEED_VALUES", "7,13,21,42,64,99")
    return [int(item) for item in raw.split(",") if item.strip()]


def main():
    with connect() as conn:
        for statement in SCHEMA:
            conn.execute(statement)
        count = conn.execute("SELECT count(*) FROM lab_values").fetchone()[0]
        if count == 0:
            with conn.cursor() as cur:
                cur.executemany(
                    "INSERT INTO lab_values (value) VALUES (%s)",
                    [(v,) for v in seed_values()],
                )
            print(f"seeded {len(seed_values())} rows")
        else:
            print(f"lab_values already has {count} rows")


if __name__ == "__main__":
    main()

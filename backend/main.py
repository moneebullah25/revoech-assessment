from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
import psycopg2
import json
import time
from typing import Optional

app = FastAPI()
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["GET"], allow_headers=["*"])

DATABASE_URL = "postgresql://postgres:password@localhost:5432/fruit_db"

def get_conn():
    return psycopg2.connect(DATABASE_URL)

@app.on_event("startup")
def seed_db():
    for _ in range(10):
        try:
            conn = get_conn()
            break
        except psycopg2.OperationalError:
            time.sleep(1)
    else:
        raise RuntimeError("Could not connect to database")
    cur = conn.cursor()
    cur.execute("""
        CREATE TABLE IF NOT EXISTS fruit (
            id SERIAL PRIMARY KEY,
            name TEXT NOT NULL,
            color TEXT NOT NULL,
            in_season BOOLEAN NOT NULL
        )
    """)
    cur.execute("SELECT COUNT(*) FROM fruit")
    if cur.fetchone()[0] == 0:
        with open("fruitList.json") as f:
            fruits = json.load(f)
        cur.executemany(
            "INSERT INTO fruit (name, color, in_season) VALUES (%s, %s, %s)",
            [(fr["name"], fr["color"], fr["in_season"]) for fr in fruits],
        )
    conn.commit()
    cur.close()
    conn.close()

@app.get("/fruit")
def list_fruit(
    color: Optional[str] = None,
    in_season: Optional[bool] = None,
    name: Optional[str] = None,
):
    conn = get_conn()
    cur = conn.cursor()
    query = "SELECT name, color, in_season FROM fruit WHERE 1=1"
    params = []
    if color:
        query += " AND color = %s"
        params.append(color)
    if in_season is not None:
        query += " AND in_season = %s"
        params.append(in_season)
    if name:
        query += " AND LOWER(name) LIKE %s"
        params.append(f"%{name.lower()}%")
    cur.execute(query, params)
    rows = cur.fetchall()
    cur.close()
    conn.close()
    return [{"name": r[0], "color": r[1], "in_season": r[2]} for r in rows]

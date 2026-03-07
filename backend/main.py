from contextlib import asynccontextmanager
from typing import Optional
import asyncio
import json
import os

import asyncpg
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

DATABASE_URL = os.getenv(
    "DATABASE_URL", "postgresql://postgres:password@localhost:5432/fruit_db"
)

pool: asyncpg.Pool = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    global pool
    for attempt in range(10):
        try:
            pool = await asyncpg.create_pool(
                DATABASE_URL,
                min_size=5,
                max_size=20,
                command_timeout=30,
            )
            break
        except Exception:
            if attempt == 9:
                raise
            await asyncio.sleep(1)

    async with pool.acquire() as conn:
        await conn.execute("""
            CREATE TABLE IF NOT EXISTS fruit (
                id     SERIAL PRIMARY KEY,
                name   TEXT NOT NULL UNIQUE,
                color  TEXT NOT NULL,
                in_season BOOLEAN NOT NULL
            )
        """)
        count = await conn.fetchval("SELECT COUNT(*) FROM fruit")
        if count == 0:
            with open("fruitList.json") as f:
                fruits = json.load(f)
            await conn.executemany(
                "INSERT INTO fruit (name, color, in_season) VALUES ($1, $2, $3)"
                " ON CONFLICT (name) DO NOTHING",
                [(fr["name"], fr["color"], fr["in_season"]) for fr in fruits],
            )

    yield
    await pool.close()


app = FastAPI(lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["GET"],
    allow_headers=["*"],
)


@app.get("/fruit")
async def list_fruit(
    color: Optional[str] = None,
    in_season: Optional[bool] = None,
    name: Optional[str] = None,
):
    query = "SELECT name, color, in_season FROM fruit WHERE 1=1"
    params: list = []
    i = 1

    if color:
        query += f" AND color = ${i}"
        params.append(color)
        i += 1
    if in_season is not None:
        query += f" AND in_season = ${i}"
        params.append(in_season)
        i += 1
    if name:
        query += f" AND LOWER(name) LIKE ${i}"
        params.append(f"%{name.lower()}%")

    async with pool.acquire() as conn:
        rows = await conn.fetch(query, *params)

    return [{"name": r["name"], "color": r["color"], "in_season": r["in_season"]} for r in rows]

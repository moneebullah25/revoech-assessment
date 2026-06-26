# CLAUDE.md — revoech-assessment

## What this project is

A full-stack fruit-list coding challenge. A React + Vite frontend fetches fruits from a FastAPI backend backed by PostgreSQL. Filters (name, color, in_season) are applied server-side and kept in sync with the browser URL query string. Nginx sits in front of the backend as a reverse proxy with response caching. A Python autoscaler script and a bash stress-test suite are included as stretch goals.

## Architecture

```
Browser (React/Vite :3000)
    → nginx :8080  (reverse proxy, 10s response cache)
        → backend :8000  (FastAPI / uvicorn, 4 workers)
            → PostgreSQL :5432  (Docker, fruit_db)
```

Docker Compose runs db + backend + nginx + frontend (built image). For local dev the frontend is usually run with `npm run dev` outside Docker.

## Key files and directories

| Path | Purpose |
|---|---|
| `backend/main.py` | FastAPI app, single `GET /fruit` endpoint with optional `color`, `in_season`, `name` query params |
| `backend/requirements.txt` | `fastapi`, `uvicorn[standard]`, `asyncpg` |
| `backend/Dockerfile` | Build context is repo root (needs `fruitList.json`); runs uvicorn with 4 workers |
| `fruitList.json` | Seed data (15 fruits). Loaded into Postgres on first startup if table is empty |
| `frontend/src/App.jsx` | All UI logic: filter state initialized from URL params, `useEffect` syncs filters → URL → API fetch |
| `frontend/vite.config.js` | Vite dev server on port 3000 |
| `frontend/Dockerfile` | Multi-stage: Node build → nginx:alpine static serve on :80 |
| `nginx/nginx.conf` | `least_conn` upstream, 10s response cache keyed on `$request_uri`, `epoll` event loop |
| `docker-compose.yml` | Services: db (postgres:16-alpine), backend, nginx, frontend |
| `autoscaler.py` | Polls `docker stats` every 10s; scales backend between 2–10 replicas based on avg CPU (up >70%, down <30%) |
| `stress-test.sh` | 8-phase autocannon stress suite hitting nginx at :8080; saves JSON reports to `stress-results/` |

## Build and run commands

### Full stack via Docker Compose (recommended)

```bash
docker compose up --build
```

- Backend API: http://localhost:8080/fruit
- Backend API docs (Swagger): http://localhost:8080/docs
- Frontend: http://localhost:3000

### Frontend dev server (outside Docker)

```bash
cd frontend
npm install
npm run dev          # http://localhost:3000
```

Note: `App.jsx` hard-codes `API = 'http://localhost:8080'`, so nginx must be running for the dev frontend to work.

### Frontend production build

```bash
cd frontend
npm run build        # output in frontend/dist/
npm run preview      # preview built output
```

### Scale backend replicas manually

```bash
docker compose up --scale backend=4 -d --no-recreate
```

### Run autoscaler (while stack is up)

```bash
python autoscaler.py   # runs from repo root
```

### Run stress tests (requires npx/autocannon and running stack)

```bash
./stress-test.sh
```

Reports land in `stress-results/` as timestamped JSON files.

## API

`GET /fruit` — returns a JSON array of fruit objects.

| Query param | Type | Behavior |
|---|---|---|
| `color` | string | Case-insensitive substring match on `color` |
| `in_season` | bool (`true`/`false`) | Exact boolean filter |
| `name` | string | Case-insensitive substring match on `name` |

Examples:
```
GET /fruit?color=red
GET /fruit?in_season=true
GET /fruit?color=red&in_season=true
GET /fruit?name=app
```

Response shape:
```json
[{ "name": "Apple", "color": "red", "in_season": true }]
```

## Database

- Engine: PostgreSQL 16 via Docker
- DB: `fruit_db`, user `postgres`, password `password`
- Table: `fruit(id SERIAL PK, name TEXT UNIQUE, color TEXT, in_season BOOLEAN)`
- Seeded automatically on first backend startup from `fruitList.json`
- Backend uses `asyncpg` with a connection pool (min 5, max 20)
- Connection retry loop (10 attempts, 1s sleep) handles Docker startup race

## Conventions and gotchas

- The backend Dockerfile's build context is the repo root (not `backend/`), because it needs to `COPY fruitList.json`. Changing the Dockerfile location or build context will break the seed step.
- `in_season` query param is parsed natively by FastAPI as `Optional[bool]` — `true`/`false` strings are converted automatically.
- `color` filter also uses `LOWER ... LIKE %value%` (substring), not exact match — same pattern as `name`.
- Nginx caches responses for 10s keyed on the full `$request_uri` (including query string). Cache-busting params like `_bust=` or `_soak=` in the stress test intentionally bypass this.
- `autoscaler.py` identifies backend containers by checking for `-backend-` in the Docker container name (Compose naming convention).
- No tests exist in this repo (the README lists "add tests" as a stretch goal).
- No linter or formatter is configured.

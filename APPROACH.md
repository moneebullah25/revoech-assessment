# Thought Process / Approach

## Stack

- **Backend**: FastAPI (Python) — simple, fast, auto-generates docs at `/docs`
- **Frontend**: React + Vite — minimal JSX components, no CSS, plain HTML elements
- **Database**: PostgreSQL via Docker

## Key Decisions

### Backend
- Used `psycopg2` directly instead of an ORM to keep it minimal and explicit
- On startup, the app creates the `fruit` table and seeds it from `fruitList.json` if empty
- Added a retry loop on DB connection to handle Docker startup ordering gracefully (even with healthcheck)
- FastAPI's native `Optional[bool]` query parameter handling automatically converts `true`/`false` strings — no manual parsing needed
- `name` filter uses `LOWER(name) LIKE %search%` for case-insensitive partial matching

### Frontend
- State is initialized from URL query params so filters survive page refresh
- `useEffect` syncs filter state → URL query string → API fetch in one shot
- `window.history.replaceState` updates the URL without triggering a reload, keeping the address bar in sync with the UI

### Docker
- Only PostgreSQL and the backend run in Docker
- The backend Dockerfile build context is the repo root so it can copy `fruitList.json` into the image
- A `healthcheck` on the `db` service ensures the backend only starts once Postgres is ready
- Frontend runs locally with `npm run dev` — no need to containerize a dev server

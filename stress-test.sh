#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
#  STRESS TEST SUITE — hits backend + db through nginx at localhost:8080
#  Phases: warmup → single-endpoint torture → filter combos → ramp-up →
#          thundering herd → cache-bust (forces DB every request) → cooldown
# ─────────────────────────────────────────────────────────────────────────────

BASE="http://localhost:8080"
REPORT_DIR="./stress-results"
mkdir -p "$REPORT_DIR"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

RED='\033[0;31m'
GRN='\033[0;32m'
YEL='\033[1;33m'
CYN='\033[0;36m'
RST='\033[0m'

pass=0
fail=0

banner() { printf "\n${CYN}══════════════════════════════════════════════════════════════${RST}\n"; printf "${YEL}  %s${RST}\n" "$1"; printf "${CYN}══════════════════════════════════════════════════════════════${RST}\n\n"; }

run_test() {
  local label="$1"; shift
  local outfile="${REPORT_DIR}/${TIMESTAMP}_$(echo "$label" | tr ' /' '_').json"

  printf "${GRN}▸ %-50s${RST}" "$label"
  if result=$(npx autocannon "$@" -j 2>/dev/null); then
    echo "$result" > "$outfile"

    req=$(echo "$result" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['requests']['average'])" 2>/dev/null || echo "?")
    lat=$(echo "$result" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['latency']['average'])" 2>/dev/null || echo "?")
    e2xx=$(echo "$result" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('2xx',0))" 2>/dev/null || echo "?")
    enon=$(echo "$result" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('non2xx',0))" 2>/dev/null || echo "?")
    errs=$(echo "$result" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('errors',0))" 2>/dev/null || echo "?")

    printf "  %s req/s  %sms lat  2xx=%s  non2xx=%s  err=%s\n" "$req" "$lat" "$e2xx" "$enon" "$errs"

    if [ "$enon" != "0" ] && [ "$enon" != "?" ] || [ "$errs" != "0" ] && [ "$errs" != "?" ]; then
      printf "    ${RED}⚠  non-2xx or errors detected${RST}\n"
      ((fail++))
    else
      ((pass++))
    fi
  else
    printf "  ${RED}FAILED${RST}\n"
    ((fail++))
  fi
}

# ── pre-flight ────────────────────────────────────────────────────────────────
banner "PRE-FLIGHT CHECK"
printf "Checking backend health... "
if curl -sf "$BASE/fruit" > /dev/null 2>&1; then
  printf "${GRN}OK${RST}\n"
else
  printf "${RED}FAIL — is docker compose up?${RST}\n"
  exit 1
fi

replicas=$(docker compose ps -q backend 2>/dev/null | wc -l | tr -d ' ')
printf "Backend replicas: ${YEL}%s${RST}\n" "$replicas"
printf "Nginx:            ${YEL}%s${RST}\n" "$(curl -sI "$BASE/fruit" | grep -i server | head -1 | tr -d '\r')"
printf "Reports dir:      ${YEL}%s${RST}\n" "$REPORT_DIR"

# ── phase 1: warmup ──────────────────────────────────────────────────────────
banner "PHASE 1 — WARMUP (low connections, prime cache + pool)"
run_test "warmup /fruit"                         "$BASE/fruit"                                  -c 200  -d 30
run_test "warmup /fruit?color=red"               "$BASE/fruit?color=red"                        -c 200  -d 30
run_test "warmup /fruit?in_season=true"          "$BASE/fruit?in_season=true"                   -c 200  -d 30
run_test "warmup /fruit?name=app"                "$BASE/fruit?name=app"                         -c 200  -d 30

# ── phase 2: single endpoint sustained load ───────────────────────────────────
banner "PHASE 2 — SUSTAINED LOAD (200 conn, 30s per endpoint)"
run_test "sustained /fruit (all)"                "$BASE/fruit"                                  -c 200 -d 30
run_test "sustained /fruit?color=red"            "$BASE/fruit?color=red"                        -c 200 -d 30
run_test "sustained /fruit?in_season=false"      "$BASE/fruit?in_season=false"                  -c 200 -d 30
run_test "sustained /fruit?name=berry"           "$BASE/fruit?name=berry"                       -c 200 -d 30

# ── phase 3: combined filters (more complex queries) ─────────────────────────
banner "PHASE 3 — COMBINED FILTERS (DB works harder)"
run_test "color+season"                          "$BASE/fruit?color=red&in_season=true"         -c 200 -d 30
run_test "color+name"                            "$BASE/fruit?color=yellow&name=an"             -c 200 -d 30
run_test "season+name"                           "$BASE/fruit?in_season=false&name=p"           -c 200 -d 30
run_test "all three filters"                     "$BASE/fruit?color=green&in_season=true&name=l" -c 200 -d 30

# ── phase 4: connection ramp-up (find the breaking point) ────────────────────
banner "PHASE 4 — RAMP-UP (escalating connections: 100→500→1000)"
run_test "ramp 100 conn"                         "$BASE/fruit"                                  -c 100  -d 30
run_test "ramp 250 conn"                         "$BASE/fruit"                                  -c 250  -d 30
run_test "ramp 500 conn"                         "$BASE/fruit"                                  -c 500  -d 30
run_test "ramp 1000 conn"                        "$BASE/fruit"                                  -c 1000 -d 30

# ── phase 5: pipelining torture (max throughput) ──────────────────────────────
banner "PHASE 5 — PIPELINING TORTURE (200 conn × 10 pipeline)"
run_test "pipeline /fruit"                       "$BASE/fruit"                                  -c 200 -d 30 -p 10
run_test "pipeline combined filters"             "$BASE/fruit?color=red&in_season=true&name=a"  -c 200 -d 30 -p 10

# ── phase 6: cache-bust (every request hits DB, no nginx cache) ──────────────
banner "PHASE 6 — CACHE BUST (unique URLs force DB hit every time)"
# autocannon supports request overrides via a body file — but simplest is
# a unique query param baked into the URL so nginx cache never matches
BUST=$(date +%s)
run_test "cache-bust /fruit"                     "$BASE/fruit?_bust=${BUST}a"                   -c 200 -d 30
run_test "cache-bust filters"                    "$BASE/fruit?color=r&name=a&_bust=${BUST}b"    -c 200 -d 30

# ── phase 7: thundering herd (cold start burst) ──────────────────────────────
banner "PHASE 7 — THUNDERING HERD (500 conn, 0 warmup, instant burst)"
run_test "herd /fruit"                           "$BASE/fruit?_herd=$(date +%s)"                -c 500 -d 30 -W 0
run_test "herd combined"                         "$BASE/fruit?color=o&in_season=true&_herd=$(date +%s)" -c 500 -d 30 -W 0

# ── phase 8: long soak (sustained pressure to surface memory leaks / pool exhaustion)
banner "PHASE 8 — SOAK TEST (200 conn, 60s continuous)"
run_test "60s soak /fruit"                       "$BASE/fruit?_soak=$(date +%s)"                -c 200 -d 60
run_test "60s soak combined"                     "$BASE/fruit?color=re&in_season=false&name=r&_soak=$(date +%s)" -c 200 -d 60

# ── results ───────────────────────────────────────────────────────────────────
banner "RESULTS"
printf "Passed: ${GRN}%d${RST}\n" "$pass"
printf "Failed: ${RED}%d${RST}\n" "$fail"
printf "Total:  %d\n" $((pass + fail))
printf "Reports saved to: ${YEL}%s${RST}\n\n" "$REPORT_DIR"

# ── post-flight: container health check ───────────────────────────────────────
banner "POST-FLIGHT — CONTAINER HEALTH"
docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"

printf "\n${YEL}DB connection pool check:${RST}\n"
docker compose exec -T db psql -U postgres -d fruit_db -c "SELECT count(*) AS active_connections FROM pg_stat_activity WHERE datname = 'fruit_db';" 2>/dev/null || echo "(could not query pg_stat_activity)"

if [ "$fail" -gt 0 ]; then
  printf "\n${RED}✗ %d test(s) had errors or non-2xx responses${RST}\n" "$fail"
  exit 1
else
  printf "\n${GRN}✓ All tests passed clean${RST}\n"
  exit 0
fi
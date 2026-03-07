#!/usr/bin/env python3
"""
Autoscaler for the backend service.
Run from the project root: python autoscaler.py

Monitors per-container CPU usage every INTERVAL seconds.
Scales between MIN_REPLICAS and MAX_REPLICAS with a cooldown between events.
"""
import json
import subprocess
import time

SERVICE = "backend"
MIN_REPLICAS = 2
MAX_REPLICAS = 10
SCALE_UP_CPU = 70.0    # % avg CPU across all backend containers → scale up
SCALE_DOWN_CPU = 30.0  # % avg CPU across all backend containers → scale down
INTERVAL = 10          # seconds between checks
COOLDOWN = 20          # seconds to wait after a scale event before acting again

_last_scale = 0.0


def backend_cpus() -> list[float]:
    out = subprocess.run(
        ["docker", "stats", "--no-stream", "--format", "{{json .}}"],
        capture_output=True, text=True,
    ).stdout
    cpus = []
    for line in out.splitlines():
        try:
            s = json.loads(line)
            if f"-{SERVICE}-" in s.get("Name", ""):
                cpus.append(float(s["CPUPerc"].rstrip("%")))
        except Exception:
            pass
    return cpus


def current_replicas() -> int:
    out = subprocess.run(
        ["docker", "compose", "ps", "-q", SERVICE],
        capture_output=True, text=True,
    ).stdout
    return len([l for l in out.splitlines() if l.strip()])


def scale_to(n: int) -> None:
    subprocess.run(
        ["docker", "compose", "up", "--scale", f"{SERVICE}={n}", "-d", "--no-recreate"],
        capture_output=True,
    )
    print(f"  → scaled {SERVICE} to {n} replicas")


def main() -> None:
    global _last_scale
    print(
        f"autoscaler started  "
        f"service={SERVICE}  min={MIN_REPLICAS}  max={MAX_REPLICAS}  "
        f"up>{SCALE_UP_CPU}%  down<{SCALE_DOWN_CPU}%  interval={INTERVAL}s"
    )
    while True:
        cpus = backend_cpus()
        if not cpus:
            print(f"[{_ts()}] no backend containers found, waiting...")
            time.sleep(INTERVAL)
            continue

        n = current_replicas()
        avg = sum(cpus) / len(cpus)
        now = time.time()
        cooling = (now - _last_scale) < COOLDOWN

        print(
            f"[{_ts()}]  replicas={n}  cpu={avg:.1f}%"
            + ("  (cooldown)" if cooling else "")
        )

        if not cooling:
            if avg > SCALE_UP_CPU and n < MAX_REPLICAS:
                new = min(n + 2, MAX_REPLICAS)
                print(f"  CPU {avg:.1f}% > {SCALE_UP_CPU}% → scaling up {n} → {new}")
                scale_to(new)
                _last_scale = now
            elif avg < SCALE_DOWN_CPU and n > MIN_REPLICAS:
                new = max(n - 1, MIN_REPLICAS)
                print(f"  CPU {avg:.1f}% < {SCALE_DOWN_CPU}% → scaling down {n} → {new}")
                scale_to(new)
                _last_scale = now

        time.sleep(INTERVAL)


def _ts() -> str:
    return time.strftime("%H:%M:%S")


if __name__ == "__main__":
    main()

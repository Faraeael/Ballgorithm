#!/usr/bin/env python3
"""Amendment 004 evidence verification.

Fails (non-zero exit) when any required recovered artifact is missing, when its
LF-normalized SHA-256 does not match `CHECKSUMS.sha256`, or when the nine frozen
pilot gates do not recompute to their recorded verdicts.

Run from the repository root:

    python specs/002-possession-simulation/amendment-004-recovery/verify_evidence.py

Verification is deliberately independent of the recovery run: it re-derives every
gate from `pilot-v4-raw.json` rather than trusting `gate-audit-recovered.json`.
"""

from __future__ import annotations

import csv
import hashlib
import json
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
CHECKSUMS = HERE / "CHECKSUMS.sha256"

REQUIRED = [
    "pilot-v3-raw.json",
    "pilot-v4-raw.json",
    "pilot-paired-recovered.csv",
    "t014-v4-raw.json",
    "gate-audit-recovered.json",
]

failures: list[str] = []


def canonical_bytes(path: pathlib.Path) -> bytes:
    """Repository-canonical bytes: LF line endings, UTF-8, no trailing rewrite."""
    raw = path.read_bytes()
    return raw.replace(b"\r\n", b"\n").replace(b"\r", b"\n")


def sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def check_required_present() -> None:
    for name in REQUIRED:
        path = HERE / name
        if not path.is_file():
            failures.append(f"missing required artifact: {name}")
        elif path.stat().st_size == 0:
            failures.append(f"empty required artifact: {name}")


def check_checksums() -> None:
    if not CHECKSUMS.is_file():
        failures.append("missing CHECKSUMS.sha256")
        return
    recorded: dict[str, str] = {}
    for line in CHECKSUMS.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        digest, _, name = line.partition("  ")
        if not digest or not name:
            failures.append(f"malformed checksum line: {line!r}")
            continue
        recorded[name] = digest

    for name, expected in recorded.items():
        path = HERE / name
        if not path.is_file():
            failures.append(f"checksum listed for missing file: {name}")
            continue
        actual = sha256_hex(canonical_bytes(path))
        if actual != expected:
            failures.append(
                f"checksum mismatch for {name}: expected {expected}, got {actual}"
            )

    for name in REQUIRED:
        if name not in recorded:
            failures.append(f"artifact not covered by CHECKSUMS.sha256: {name}")


def check_gates() -> None:
    raw = json.loads((HERE / "pilot-v4-raw.json").read_text(encoding="utf-8"))
    rows = raw["rows"]
    if len(rows) != 280:
        failures.append(f"expected 280 pilot rows, found {len(rows)}")
        return

    def col(key: str) -> list[float]:
        return [float(r[key]) for r in rows]

    n = len(rows)
    of = col("offensiveFoulTov")
    tov = col("tov")
    completed = col("completed")
    fga = col("fga")
    fgm = col("fgm")
    three_pa = col("threePa")
    three_pm = col("threePm")
    sc = col("shotClockTov")
    home_fga = col("homeFga")
    away_fga = col("awayFga")

    def median(values: list[float]) -> float:
        ordered = sorted(values)
        mid = len(ordered) // 2
        if len(ordered) % 2:
            return ordered[mid]
        return (ordered[mid - 1] + ordered[mid]) / 2.0

    computed = {
        "G1": sum(of) / n / 2.0,
        "G2": sum(of) / sum(tov),
        "G3": sum(tov) / sum(completed) * 100.0,
        "G4": sum(sc) / n,
        "G5": sum(completed) / n / 2.0,
        "G6": median(home_fga + away_fga),
        "G7": sum(three_pa) / sum(fga),
        "G8": (sum(fgm) + 0.5 * sum(three_pm)) / sum(fga),
    }
    bounds = {
        "G1": (1.80, 2.60),
        "G2": (0.100, 0.160),
        "G3": (15.0, 19.5),
        "G4": (3.0, 5.5),
        "G5": (100.0, 106.0),
        "G6": (88.0, 95.0),
        "G7": (0.380, 0.450),
        "G8": (0.510, 0.540),
    }

    audit = json.loads(
        (HERE / "gate-audit-recovered.json").read_text(encoding="utf-8")
    )
    recorded = {g["id"]: g for g in audit["gates"]}

    for gate_id, value in computed.items():
        low, high = bounds[gate_id]
        verdict = "PASS" if low <= value <= high else "FAIL"
        if verdict != "PASS":
            failures.append(
                f"{gate_id} recomputes to {value:.6f}, outside [{low}, {high}]"
            )
        if gate_id in recorded:
            if recorded[gate_id]["verdict"] != verdict:
                failures.append(
                    f"{gate_id} recorded verdict {recorded[gate_id]['verdict']} "
                    f"disagrees with recomputed {verdict}"
                )

    t14 = json.loads((HERE / "t014-v4-raw.json").read_text(encoding="utf-8"))
    summaries = {s["id"]: s for s in t14["summaries"]}
    for experiment in ("E1", "E2", "E3", "E4", "E5", "E6"):
        if experiment not in summaries:
            failures.append(f"t014 artifact missing {experiment}")
            continue
        if summaries[experiment]["verdict"] != "PASSED":
            failures.append(
                f"{experiment} verdict is {summaries[experiment]['verdict']}, not PASSED"
            )


def check_provenance() -> None:
    manifest = json.loads(
        (HERE / "pilot-v4-raw.json").read_text(encoding="utf-8")
    )
    if manifest.get("seedSchedule") != "1 + ((97*m + 17*s) mod 200)":
        failures.append("unexpected seed schedule in pilot-v4-raw.json")
    if manifest.get("directedMatchups") != 56 or manifest.get("slotsPerMatchup") != 5:
        failures.append("unexpected cohort shape in pilot-v4-raw.json")
    seeds = [r["seed"] for r in manifest["rows"]]
    if any(s < 1 or s > 200 for s in seeds):
        failures.append("held-out or out-of-range seed found in development pilot")
    pairs = {(r["matchupIndex"], r["seed"]) for r in manifest["rows"]}
    if len(pairs) != len(manifest["rows"]):
        failures.append("duplicate (matchupIndex, seed) pair in development pilot")
    matchups = {r["matchupIndex"] for r in manifest["rows"]}
    if matchups != set(range(56)):
        failures.append("pilot does not cover exactly matchups 0..55")


def main() -> int:
    check_required_present()
    check_checksums()
    if not failures:
        check_gates()
        check_provenance()

    if failures:
        print("EVIDENCE VERIFICATION FAILED")
        for item in failures:
            print(f"  - {item}")
        return 1

    print("EVIDENCE VERIFICATION PASSED")
    print(f"  artifacts checked: {len(REQUIRED)}")
    print("  gates recomputed:  G1-G8 from pilot-v4-raw.json, G9 from t014-v4-raw.json")
    print("  provenance:        development seeds 1..200, matchups 0..55, 280 unique slots")
    return 0


if __name__ == "__main__":
    sys.exit(main())

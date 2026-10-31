#!/usr/bin/env python3
"""Amendment 004 held-out evidence verification.

Exit status is non-zero when a required artifact is missing, a recorded
LF-normalized SHA-256 does not match, the seed/pairing/version provenance is wrong,
a per-game identity fails, or a frozen gate recomputed from the RAW rows disagrees
with `heldout-summary.json`. G1-G8 are recomputed from raw game rows. G9 is
corroborated from the 1,200 raw `perSeed` T014 records (counts, seeds, mean
differences, expected sign, independent paired t-test with Holm); the frozen
permutation p-values and Holm values are runner-reported and are NOT reproduced here.

Run from the repository root:
    python specs/002-possession-simulation/amendment-004-heldout/verify_heldout.py
Add `--git-ref <commit>` to verify committed blobs (`git show <ref>:<path>`)
instead of working-tree files.
"""
import csv
import hashlib
import math
import io
import json
import os
import statistics
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REL = "specs/002-possession-simulation/amendment-004-heldout"
REQUIRED = [
    "v3-heldout-raw.json", "v4-heldout-raw.json", "t014-v4-fresh-raw.json",
    "heldout-paired.csv", "heldout-summary.json", "seed-manifest.csv",
    "execution-metadata.json", "heldout-summary-supplemental-dof.json",
    "PROTOCOL-DEVIATION.md", "amendment-004-heldout-protocol.md",
    "analyze_heldout.py", "supplemental_inference.py",
]
ENV = {"G1": (1.80, 2.60), "G2": (0.100, 0.160), "G3": (15.0, 19.5), "G4": (3.0, 5.5),
       "G5": (100.0, 106.0), "G6": (88.0, 95.0), "G7": (0.380, 0.450), "G8": (0.510, 0.540)}
errors = []
ref = sys.argv[sys.argv.index("--git-ref") + 1] if "--git-ref" in sys.argv else None


def read(name):
    if ref:
        out = subprocess.run(["git", "show", f"{ref}:{REL}/{name}"], capture_output=True, check=True)
        raw = out.stdout
    else:
        with open(os.path.join(HERE, name), "rb") as f:
            raw = f.read()
    return raw.replace(b"\r\n", b"\n")


def fail(msg):
    errors.append(msg)


def main():
    data = {}
    for n in REQUIRED + ["CHECKSUMS.sha256"]:
        try:
            data[n] = read(n)
        except Exception:
            fail(f"missing artifact {n}")
            continue
        if not data[n]:
            fail(f"empty artifact {n}")
    if errors:
        return

    recorded = {}
    for line in data["CHECKSUMS.sha256"].decode().splitlines():
        h, name = line.split("  ", 1)
        recorded[name] = h
    for n in REQUIRED:
        if n not in recorded:
            fail(f"{n} not covered by CHECKSUMS.sha256")
        elif hashlib.sha256(data[n]).hexdigest() != recorded[n]:
            fail(f"checksum mismatch {n}")

    v3 = json.loads(data["v3-heldout-raw.json"])
    v4 = json.loads(data["v4-heldout-raw.json"])
    t14 = json.loads(data["t014-v4-fresh-raw.json"])
    summary = json.loads(data["heldout-summary.json"])
    r3, r4 = v3["rows"], v4["rows"]

    if len(r3) != 1120 or len(r4) != 1120:
        fail(f"row counts {len(r3)}/{len(r4)}")
    if v3.get("cohort") != "heldout" or v4.get("cohort") != "heldout":
        fail("cohort flag is not heldout")

    manifest = list(csv.DictReader(io.StringIO(data["seed-manifest.csv"].decode())))
    seeds = [10001 + ((137 * i + 23) % 600) for i in range(1120)]
    if [int(m["seed"]) for m in manifest] != seeds:
        fail("seed-manifest.csv does not match the frozen schedule")
    counts = {}
    for s in seeds:
        counts[s] = counts.get(s, 0) + 1
    if len(counts) != 600 or min(seeds) < 10001 or max(seeds) > 10600:
        fail("seed uniqueness/range")
    if sorted(set(counts.values())) != [1, 2] or sum(1 for c in counts.values() if c == 2) != 520:
        fail("520/80 reuse structure")

    for i, (a, b) in enumerate(zip(r3, r4)):
        if a["seed"] != seeds[i] or b["seed"] != seeds[i] or a["slot"] != i or b["slot"] != i:
            fail(f"slot {i}: seed/slot does not follow the frozen schedule")
            break
        if (a["matchupIndex"], a["orientation"], a["gameId"]) != (b["matchupIndex"], b["orientation"], b["gameId"]):
            fail(f"slot {i}: v3/v4 pairing mismatch")
            break
        if a["inputFingerprint"] == b["inputFingerprint"]:
            fail(f"slot {i}: fingerprints equal across versions")
            break
    if {r["simulationVersion"] for r in r3} != {3} or {r["simulationVersion"] for r in r4} != {4}:
        fail("simulation versions are not 3/4")
    if len({r["inputFingerprint"] for r in r3 + r4}) != 2240:
        fail("input fingerprints are not 2240 distinct values")

    for tag, rows in (("v3", r3), ("v4", r4)):
        for r in rows:
            if r["tov"] != r["shotClockTov"] + r["stealTov"] + r["nonStealTov"] + r["offensiveFoulTov"]:
                fail(f"{tag} slot {r['slot']}: turnover categories do not sum to tov")
                break
            if r["homeScore"] + r["awayScore"] != r["combinedPoints"]:
                fail(f"{tag} slot {r['slot']}: points identity")
                break
            ctx = r["freshViolations"] + r["orebViolations"] + r["retFoulViolations"]
            if ctx != r["shotClockTov"]:
                fail(f"{tag} slot {r['slot']}: context violations {ctx} != shotClockTov {r['shotClockTov']}")
                break

    n = len(r4)
    s = lambda k: sum(r[k] for r in r4)
    values = {
        "G1": s("offensiveFoulTov") / (2 * n),
        "G2": s("offensiveFoulTov") / s("tov"),
        "G3": 100 * s("tov") / s("completed"),
        "G4": s("shotClockTov") / n,
        "G5": s("completed") / (2 * n),
        "G6": statistics.median([r["homeFga"] for r in r4] + [r["awayFga"] for r in r4]),
        "G7": s("threePa") / s("fga"),
        "G8": (s("fgm") + 0.5 * s("threePm")) / s("fga"),
    }
    for g, (lo, hi) in ENV.items():
        rec = summary["frozenGates"][g]
        if abs(rec["value"] - values[g]) > 1e-9:
            fail(f"{g}: summary value {rec['value']} != recomputed {values[g]}")
        verdict = "PASS" if lo <= values[g] <= hi else "FAIL"
        if rec["verdict"] != verdict:
            fail(f"{g}: summary verdict {rec['verdict']} != recomputed {verdict}")

    exps = {x["id"]: x["verdict"] for x in t14["summaries"]}
    g9 = (t14.get("seedOffset") == 10000 and t14.get("firstSeed") == 10001
          and t14.get("lastSeed") == 10200 and t14.get("simulationVersion") == 4
          and sorted(exps) == ["E1", "E2", "E3", "E4", "E5", "E6"]
          and all(v == "PASSED" for v in exps.values()))
    per = t14["perSeed"]
    if len(per) != 1200:
        fail(f"T014 perSeed records {len(per)} != 1200")
    pvals = {}
    for summ in t14["summaries"]:
        e = summ["id"]
        valid = [p for p in per if p["experiment"] == e and p["status"] == "valid"]
        seeds14 = [p["seed"] for p in valid]
        if len(seeds14) != len(set(seeds14)) or any(not 10001 <= x <= 10200 for x in seeds14):
            fail(f"{e}: perSeed seeds duplicated or outside 10001-10200")
        if len(valid) != summ["validPairs"] or len(valid) < t14["minimumValidPairs"]:
            fail(f"{e}: valid pairs {len(valid)} vs summary {summ['validPairs']}")
            continue
        d = [p["pairedDifference"] for p in valid]
        if any(abs(p["interventionMetric"] - p["baselineMetric"] - p["pairedDifference"]) > 1e-12 for p in valid):
            fail(f"{e}: pairedDifference != interventionMetric - baselineMetric")
        mean = sum(d) / len(d)
        if abs(mean - summ["meanDifference"]) > 1e-9:
            fail(f"{e}: mean difference {mean} != summary {summ['meanDifference']}")
        sign = {"increase": 1, "decrease": -1}[summ["expectedDirection"]]
        if mean * sign <= 0:
            fail(f"{e}: observed sign contradicts expected direction")
        sd = statistics.stdev(d)
        t = mean / (sd / len(d) ** 0.5) if sd > 0 else float("inf")
        pvals[e] = math.erfc(abs(t) / math.sqrt(2))  # normal approx, n >= 100
    ordered = sorted(pvals.items(), key=lambda kv: kv[1])
    running = 0.0
    for rank, (e, p) in enumerate(ordered):
        running = max(running, min(1.0, p * (len(ordered) - rank)))
        if running >= 0.05:
            fail(f"{e}: independent Holm-adjusted t-test p {running:.3g} >= 0.05")
    if summary["frozenGates"]["G9"]["verdict"] != ("PASS" if g9 else "FAIL"):
        fail("G9 verdict disagrees with the raw fresh T014 run")

    for g in list(ENV) + ["G9"]:
        print(f"  {g}: {summary['frozenGates'][g]['verdict']}")
    return values


if __name__ == "__main__":
    main()
    if errors:
        print("EVIDENCE VERIFICATION FAILED")
        for e in errors:
            print(" -", e)
        sys.exit(1)
    print("EVIDENCE VERIFICATION PASSED")
    print("  source:", ref or "working tree", "| artifacts:", len(REQUIRED),
          "| primary cohort: 2240 games (1120 v3 + 1120 v4), 600 seeds"
          " | fresh T014: 1400 sims | total simulator executions: 3640")

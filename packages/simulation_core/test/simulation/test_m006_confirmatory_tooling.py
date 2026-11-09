import copy
import json
import math
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

TOOL_DIR = Path(__file__).resolve().parent.parent.parent / "tool"
ANALYZER_SCRIPT = TOOL_DIR / "m006_analyze_paired.py"
FINALIZER_SCRIPT = TOOL_DIR / "m006_confirmatory_finalizer.py"

class TestConfirmatoryTooling(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # Create minimal synthetic data fixture
        cls.temp_dir = tempfile.TemporaryDirectory()
        cls.dpath = Path(cls.temp_dir.name)

        # Base valid manifest (10 games: 1..10)
        cls.manifest_a = cls.dpath / "manifest_a.csv"
        with open(cls.manifest_a, "w") as f:
            f.write("seed,gameId,leagueSeed,homeTeamId,awayTeamId,rules,rotationPreset,context\n")
            for s in range(1, 11):
                f.write(f"{s},game-{s},20261028,team-1,team-2,standard,balanced,context-a-main\n")

        cls.manifest_b = cls.dpath / "manifest_b.csv"
        with open(cls.manifest_b, "w") as f:
            f.write("seed,gameId,leagueSeed,homeTeamId,awayTeamId,rules,rotationPreset,type,context\n")
            for s in range(1, 11):
                f.write(f"{s},game-{s},20261028,team-1,team-2,standard,balanced,synthetic-stretch-five,context-b-stretch-five\n")

        # Base valid game records with realistic non-zero variance
        def make_game(s, v="v6", context="A"):
            jitter = (s % 3 - 1) * 0.005
            v_jitter = (s % 4 - 1.5) * 0.002 if v == "v7" else 0.0
            pts_jitter = (s % 3 - 1) * 2 + (1 if v == "v7" else 0)
            return {
                "seed": s,
                "gameId": f"game-{s}",
                "totalPoints": 220 + pts_jitter,
                "possessions": 200,
                "eFG": 0.54 + jitter + (0.002 if v == "v7" else 0),
                "fga": 180,
                "threePa": 75,
                "threePointShare": 0.40,
                "turnoversPer100": 16.0,
                "fta": 35,
                "primaryShare": (0.23 if v == "v6" else 0.28) + v_jitter,
                "secondaryShare": (0.22 if v == "v6" else 0.23) + v_jitter,
                "neutralShare": 0.55 if v == "v6" else 0.49,
                "weakShooterThreePointShare": (0.36 if v == "v6" else 0.31) + v_jitter,
                "weakEligible": True,
                "stretchBigThreePointShare": 0.36 if v == "v6" else 0.38,
                "stretchEligible": True,
                "stretchCenterThreePointShare": (0.35 if v == "v6" else 0.38) + v_jitter,
                "registeredCenterBigThreePointShare": (0.35 if v == "v6" else 0.38) + v_jitter,
                "center1Fga": 12,
                "center2Fga": 11,
                "regCenter1BigFga": 12,
                "regCenter2BigFga": 11,
                "accountingConsistent": True,
            }

        cls.v6_a_games = [make_game(s, "v6", "A") for s in range(1, 11)]
        cls.v7_a_games = [make_game(s, "v7", "A") for s in range(1, 11)]

        cls.v6_b_games = [make_game(s, "v6", "B") for s in range(1, 11)]
        cls.v7_b_games = [make_game(s, "v7", "B") for s in range(1, 11)]

        cls.v6_a_file = cls.dpath / "v6_a.json"
        cls.v7_a_file = cls.dpath / "v7_a.json"
        cls.v6_b_file = cls.dpath / "v6_b.json"
        cls.v7_b_file = cls.dpath / "v7_b.json"

        cls.v6_a_file.write_text(json.dumps(cls.v6_a_games))
        cls.v7_a_file.write_text(json.dumps(cls.v7_a_games))
        cls.v6_b_file.write_text(json.dumps(cls.v6_b_games))
        cls.v7_b_file.write_text(json.dumps(cls.v7_b_games))

    @classmethod
    def tearDownClass(cls):
        cls.temp_dir.cleanup()

    def run_analyzer(self, v6_f, v7_f, manifest_f, paired_f, ctx="A", sum_f=None, extra_args=None):
        if sum_f is None:
            sum_f = self.dpath / f"summary_{ctx}.json"
        cmd = [
            sys.executable, str(ANALYZER_SCRIPT),
            f"--v6={v6_f}", f"--v7={v7_f}",
            f"--manifest={manifest_f}", f"--paired-csv={paired_f}",
            f"--context={ctx}", f"--summary-out={sum_f}",
        ]
        if extra_args:
            cmd.extend(extra_args)
        return subprocess.run(cmd, capture_output=True, text=True)

    def run_finalizer(self, sum_a_f, sum_b_f, out_json=None, out_rep=None, extra_args=None):
        if out_json is None:
            out_json = self.dpath / "decision.json"
        if out_rep is None:
            out_rep = self.dpath / "decision.md"
        cmd = [
            sys.executable, str(FINALIZER_SCRIPT),
            f"--context-a={sum_a_f}", f"--context-b={sum_b_f}",
            f"--out-json={out_json}", f"--out-report={out_rep}",
        ]
        if extra_args:
            cmd.extend(extra_args)
        return subprocess.run(cmd, capture_output=True, text=True)

    def test_01_valid_execution(self):
        # Context A
        paired_a = self.dpath / "paired_a.csv"
        sum_a = self.dpath / "sum_a.json"
        res_a = self.run_analyzer(self.v6_a_file, self.v7_a_file, self.manifest_a, paired_a, "A", sum_a)
        self.assertEqual(res_a.returncode, 0, msg=res_a.stderr)
        self.assertTrue(sum_a.exists())

        # Context B
        paired_b = self.dpath / "paired_b.csv"
        sum_b = self.dpath / "sum_b.json"
        res_b = self.run_analyzer(self.v6_b_file, self.v7_b_file, self.manifest_b, paired_b, "B", sum_b)
        self.assertEqual(res_b.returncode, 0, msg=res_b.stderr)
        self.assertTrue(sum_b.exists())

        # Finalizer
        dec_json = self.dpath / "dec.json"
        dec_md = self.dpath / "dec.md"
        res_fin = self.run_finalizer(sum_a, sum_b, dec_json, dec_md)
        self.assertEqual(res_fin.returncode, 0, msg=res_fin.stderr)
        data = json.loads(dec_json.read_text())
        self.assertEqual(data["verdict"], "PASSED")

    def test_02_shuffled_export_ordering(self):
        # Shuffle v7 export array order
        shuffled = copy.deepcopy(self.v7_a_games)
        shuffled.reverse() # completely reversed
        shuffled_f = self.dpath / "v7_shuffled.json"
        shuffled_f.write_text(json.dumps(shuffled))

        paired_orig = self.dpath / "paired_orig.csv"
        sum_orig = self.dpath / "sum_orig.json"
        self.run_analyzer(self.v6_a_file, self.v7_a_file, self.manifest_a, paired_orig, "A", sum_orig)

        paired_shuf = self.dpath / "paired_shuf.csv"
        sum_shuf = self.dpath / "sum_shuf.json"
        res = self.run_analyzer(self.v6_a_file, shuffled_f, self.manifest_a, paired_shuf, "A", sum_shuf)
        self.assertEqual(res.returncode, 0)

        # Output paired CSV must be identical because pairing is by seed identity!
        self.assertEqual(paired_orig.read_text(), paired_shuf.read_text())
    def test_03_duplicate_seed_rejected(self):
        dups = copy.deepcopy(self.v7_a_games)
        dups[-1]["seed"] = dups[0]["seed"] # same length (10), but duplicate seed 1
        dup_f = self.dpath / "dup.json"
        dup_f.write_text(json.dumps(dups))
        res = self.run_analyzer(self.v6_a_file, dup_f, self.manifest_a, self.dpath / "p.csv", "A")
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("Duplicate seed", res.stderr)
    def test_04_missing_seed_rejected(self):
        miss = copy.deepcopy(self.v7_a_games[:-1]) # only 9 games
        miss_f = self.dpath / "miss.json"
        miss_f.write_text(json.dumps(miss))
        res = self.run_analyzer(self.v6_a_file, miss_f, self.manifest_a, self.dpath / "p.csv", "A")
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("games, expected 10", res.stderr)

    def test_05_extra_seed_rejected(self):
        extra = copy.deepcopy(self.v7_a_games)
        extra.append({"seed": 999, "gameId": "game-999"})
        extra_f = self.dpath / "extra.json"
        extra_f.write_text(json.dumps(extra))
        res = self.run_analyzer(self.v6_a_file, extra_f, self.manifest_a, self.dpath / "p.csv", "A")
        self.assertNotEqual(res.returncode, 0)

    def test_06_manifest_hash_check(self):
        res = self.run_analyzer(
            self.v6_a_file, self.v7_a_file, self.manifest_a, self.dpath / "p.csv", "A",
            extra_args=["--expected-manifest-sha=0000000000000000000000000000000000000000000000000000000000000000"]
        )
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("Manifest SHA mismatch", res.stderr)

    def test_07_mismatched_game_id_rejected(self):
        bad_id = copy.deepcopy(self.v7_a_games)
        bad_id[0]["gameId"] = "wrong-id-1"
        bad_id_f = self.dpath / "bad_id.json"
        bad_id_f.write_text(json.dumps(bad_id))
        res = self.run_analyzer(self.v6_a_file, bad_id_f, self.manifest_a, self.dpath / "p.csv", "A")
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("Game ID mismatch", res.stderr)

    def test_08_broken_accounting_rejected(self):
        broken = copy.deepcopy(self.v7_a_games)
        broken[2]["accountingConsistent"] = False
        broken_f = self.dpath / "broken.json"
        broken_f.write_text(json.dumps(broken))
        res = self.run_analyzer(self.v6_a_file, broken_f, self.manifest_a, self.dpath / "p.csv", "A")
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("accounting inconsistent", res.stderr)

    def test_09_zero_denominators_handled(self):
        zden_v6 = copy.deepcopy(self.v6_a_games)
        zden_v7 = copy.deepcopy(self.v7_a_games)
        # Set weak shooter share to None (0 attempts) in 2 games
        zden_v6[0]["weakShooterThreePointShare"] = None
        zden_v7[0]["weakShooterThreePointShare"] = None
        zden_v6[1]["weakShooterThreePointShare"] = None
        zden_v7[1]["weakShooterThreePointShare"] = 0.25 # asymmetric undefined

        f6 = self.dpath / "zden6.json"
        f7 = self.dpath / "zden7.json"
        f6.write_text(json.dumps(zden_v6))
        f7.write_text(json.dumps(zden_v7))

        sum_f = self.dpath / "zden_sum.json"
        res = self.run_analyzer(f6, f7, self.manifest_a, self.dpath / "p.csv", "A", sum_f)
        self.assertEqual(res.returncode, 0)
        data = json.loads(sum_f.read_text())
        # Total defined should be 8 (10 - 2)
        self.assertEqual(data["endpoints"]["weakShooterThreePointShare"]["n"], 8)

    def test_10_endpoint_failure_causes_FAILED(self):
        # Set primary creator difference to fail H0: delta <= +0.030
        fail_v7 = copy.deepcopy(self.v7_a_games)
        for g in fail_v7:
            g["primaryShare"] = 0.23 + (g["seed"] % 4 - 1.5) * 0.002
        f7 = self.dpath / "fail_ep7.json"
        f7.write_text(json.dumps(fail_v7))
        sum_a = self.dpath / "sum_fail_a.json"
        self.run_analyzer(self.v6_a_file, f7, self.manifest_a, self.dpath / "p.csv", "A", sum_a)

        # Context B passes
        sum_b = self.dpath / "sum_b.json"
        self.run_analyzer(self.v6_b_file, self.v7_b_file, self.manifest_b, self.dpath / "p.csv", "B", sum_b)

        res = self.run_finalizer(sum_a, sum_b)
        self.assertEqual(res.returncode, 1) # Nonzero exit code on failure
        data = json.loads((self.dpath / "decision.json").read_text())
        self.assertEqual(data["verdict"], "FAILED")
        self.assertFalse(data["all_hypotheses_rejected"])

    def test_11_guardrail_failure_causes_FAILED(self):
        # Set totalPoints delta = +10.0 (outside +/-2.5 margin)
        fail_g7 = copy.deepcopy(self.v7_a_games)
        for g in fail_g7:
            g["totalPoints"] = g["totalPoints"] + 10
        f7 = self.dpath / "fail_g7.json"
        f7.write_text(json.dumps(fail_g7))
        sum_a = self.dpath / "sum_fail_guard.json"
        self.run_analyzer(self.v6_a_file, f7, self.manifest_a, self.dpath / "p.csv", "A", sum_a)

        sum_b = self.dpath / "sum_b.json"
        self.run_analyzer(self.v6_b_file, self.v7_b_file, self.manifest_b, self.dpath / "p.csv", "B", sum_b)

        res = self.run_finalizer(sum_a, sum_b)
        self.assertEqual(res.returncode, 1)
        data = json.loads((self.dpath / "decision.json").read_text())
        self.assertEqual(data["verdict"], "FAILED")
        self.assertFalse(data["all_guardrails_passed"])

    def test_12_insufficient_exposure_causes_INSUFFICIENT(self):
        # Set all games to weakEligible = False
        inelig_v7 = copy.deepcopy(self.v7_a_games)
        for g in inelig_v7:
            g["weakEligible"] = False
        f7 = self.dpath / "inelig.json"
        f7.write_text(json.dumps(inelig_v7))
        sum_a = self.dpath / "sum_inelig.json"
        self.run_analyzer(self.v6_a_file, f7, self.manifest_a, self.dpath / "p.csv", "A", sum_a)

        sum_b = self.dpath / "sum_b.json"
        self.run_analyzer(self.v6_b_file, self.v7_b_file, self.manifest_b, self.dpath / "p.csv", "B", sum_b)

        res = self.run_finalizer(sum_a, sum_b)
        self.assertEqual(res.returncode, 1)
        data = json.loads((self.dpath / "decision.json").read_text())
        self.assertEqual(data["verdict"], "INSUFFICIENT")

    def test_13_missing_context_or_invalid_flag_causes_INVALID(self):
        # Missing context B file
        res = self.run_finalizer(self.dpath / "sum_a.json", self.dpath / "nonexistent.json")
        self.assertEqual(res.returncode, 2)
        self.assertIn("not found", res.stderr)

        # Context A file with invalid context flag
        bad_ctx = json.loads((self.dpath / "sum_a.json").read_text())
        bad_ctx["context"] = "WRONG"
        bad_ctx_f = self.dpath / "bad_ctx.json"
        bad_ctx_f.write_text(json.dumps(bad_ctx))
        res2 = self.run_finalizer(bad_ctx_f, self.dpath / "sum_b.json")
        self.assertEqual(res2.returncode, 2)
        self.assertIn("invalid context flag", res2.stderr)

if __name__ == "__main__":
    unittest.main()

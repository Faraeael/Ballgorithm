# M004 Limitations and Non-Claims

M004 delivers a verified, deterministic foundation for player participation. It does not
deliver a finished product. The following limits are part of the acceptance record.

## 1. UI polish deferred

The results UI is functionally usable and owner-approved as a functional baseline, but
still prototype-level. Deferred:

- tall player-statistics rows and large vertical whitespace;
- dense, technical disclosure paragraph;
- stronger visual hierarchy and basketball branding;
- further usability refinement and accessibility polish.

No UI change is authorized under T10.

## 2. Android debug jank

Physical debug session observations:

- Choreographer warning: 157 skipped frames;
- Choreographer warning: 33 skipped frames.

Triggering operations, frame-time distribution and cause are unmeasured. No profile-mode
benchmark, release-mode performance, memory or battery measurement exists.

**DEBUG-SESSION JANK OBSERVED — PRODUCTION PERFORMANCE NOT MEASURED.**

The warnings are not dismissed as vendor noise, and no release performance defect is
claimed from debug logs alone. No optimization/profiling is authorized here.

## 3. Gameplay realism limitations

Not modelled:

- regular tactical rotations in simulator output;
- fatigue/stamina systems;
- coaching AI;
- user-controlled substitutions;
- technical-foul penalties for depleted-roster continuation;
- NBA-level realism.

Tactical `Substitution` events are ledger-valid but the simulator emits only foul-out
handling. T08 observed 189 of 200 games with at least one disqualification; this is a
descriptive realism concern and a future investigation, not a proven defect.

No AC09/AC10 recertification and no NBA calibration acceptance is claimed. Confidence
intervals in T08 describe paired differences; they do not establish realism or
equivalence.

## 4. Historical and release limitations

- v5 does not transparently deserialize v4 ledgers (`unsupportedEventSchemaVersion`).
- Historical fixtures remain independently pinned and must be verified by their own
  builds.
- No database persistence, seasons, contracts, trades or networking.
- No production or release authorization; no signing or store-readiness work.

## 5. Verification caveats

- AC-M004-12 is now PASS: the real replacement path is observed with a passive draw
  counter (zero draws), same-slot tie-break is asserted against an independent oracle,
  and a 7-player roster fixture exercises the first-eligible roster-order fallback.
  The instrumentation adds one integer increment per PRNG draw and is not
  performance-benchmarked.
- AC-M004-19 verifies fixture/content preservation; a historical suite-count comparison
  is not reconstructed.
- AC-M004-24's zero-second entrant at 360/393/430 was verified with a transient local
  test that was not committed (file removed); the committed three-width tests cover
  substitute rows, `MIN`, hidden non-participants and disclosure.
- AC-M004-29 is assessed only on T03-era evidence (`8618550`), not on the seed-15
  regression added later in `ee50aca`.
- T08 raw evidence lives outside Git at `E:\ballgorithm-t08-artifacts`; if that path is
  lost, checksums cannot be re-verified from the repository alone.

## 5a. Resolved acceptance gaps

- **AC-M004-15 (resolved by amendment).** The superseded "typed failure on mutated totals"
  evidence was unreachable. The owner approved an evidence-only amendment on 2026-11-03:
  positive conservation tests, typed reducer negative tests, and the invariant proof that
  completed-game minute totals always equal `5 × Σ periodLengths`; the accounting guard
  remains defence-in-depth. Conservation behavior is unchanged.
- **AC-M004-24 (resolved).** Commit `9f5465d` adds permanent three-viewport regressions
  (360×640, 393×852, 430×932) for the validated zero-second entrant.

## 6. Explicit non-claims

- No NBA realism claim.
- No AC09/AC10 re-certification.
- No Android performance, memory or battery certification.
- No production, release or store-readiness claim.
- No claim that the current UI is final product design.
- No claim that T08 CIs establish equivalence.

## 7. Recommended next-milestone work

1. Investigate disqualification frequency and participation realism with a separately
   approved cohort; do not tune coefficients from T08 post hoc.
2. Measure Android performance in profile/release builds before any performance claim.
3. Improve results-screen density, disclosure readability and branding under a dedicated
   UI task with updated widget tests.
4. Keep T08 raw evidence and its checksums archived with the release evidence set.

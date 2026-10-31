# AGENTS.md — Ballgorithm

> Repository instructions for AI coding agents (including OMP). OMP normally discovers a repository-root `AGENTS.md` at session start; verify/reload it when created mid-session. This is a governance document, **not** authorization to implement a task or a substitute for the machine's OMP configuration.

## 1. Mission and product boundaries

Ballgorithm is an offline-first, deterministic basketball management simulation. The client is built with Flutter; the simulation engine is pure Dart under `packages/simulation_core`. Current priority is **trustworthy basketball simulation**, not UI expansion or superficial test-count growth. Mobile (especially Android) is the primary product target, although the core is tested headlessly and across Dart VM/Chrome.

- **Specification-driven development (SDD):** no feature or simulation rule change without a reviewed specification/amendment, an authorized task, and recorded validation evidence.
- **Basketball realism is a measured claim:** tests can establish invariants and determinism, but only statistical evaluation and owner review can approve realism.
- **Do not copy Basketball-GM or another game's protected code/assets.** Public ideas and observable behavior may inform an independently designed, documented implementation after rights and license review.
- **Preserve M001:** its league-generation vectors, snapshot format, public contracts, and PRNG behavior must not change as a side effect of M002 work.
- **Offline first:** no mandatory remote service, telemetry, login, or data dependency in the simulation core.
- No unlicensed real league, team, or player names, logos, datasets, or branding.

## 2. Read this first / authority hierarchy

Before design, code, tests, or documentation changes:

1. Check `git status --short --branch`, current commit, worktree, and the task's expected baseline. Never assume a branch, a SHA, or a clean tree.
2. Read `.specify/memory/constitution.md`.
3. Read the relevant `specs/NNN-*/spec.md`, `plan.md`, `tasks.md`, `design-decisions.md`, `acceptance-matrix.md`, calibration documents, and approved amendments/evidence.
4. Inspect actual source and tests. Historical planning prose can be stale; distinguish a *frozen design document's original status* from current execution evidence in `tasks.md` and task reports.
5. Confirm the **specific owner authorization** for the next task, including its allowed files, test scope, branch, and whether it is design-only or implementation.

**Precedence:** follow the constitution and approved/frozen specifications, the owner's latest explicit authorization within those rules, current task/evidence status, and then this AGENTS.md. The owner may explicitly approve a formal spec amendment; an informal instruction is not permission to silently bypass a non-negotiable invariant. If controlling sources materially conflict, report the conflict and stop the affected change rather than guessing.

Do not treat the mere presence of an unchecked task, a proposed amendment, or a passing test as permission to implement, rebaseline, or sign off a milestone.

## 3. Current project checkpoint (2026-10-31; reverify before acting)

- Repository: `Faraeael/Ballgorithm`.
- Active M002 integration branch: `develop/m002`; reported local worktree: `E:\ballgorithm-dev`. As of the 2026-10-31 OMP verification, `AGENTS.md` was present only in `E:\basketball-manager-sdd` on the historical `docs/m002-frozen-spec` branch; **the active development worktree was missing this file**. Install this updated file at `E:\ballgorithm-dev\AGENTS.md` before starting the next development session. Verify locally; the remote branch may lag or differ from a local worktree.
- M001 league/player foundation: accepted **GO** baseline.
- M002 possession simulation: **T004–T015 have been implemented/executed** according to `specs/002-possession-simulation/tasks.md`; M002 is **not closed**.
- T014 / **AC09:** historical v1 E4 ball-handling experiment was inconclusive; a v2 development rerun passed, but do **not** silently rewrite the frozen result or declare overall AC09 signed off.
- T015 / **AC10:** 1,120-game calibration was executed, but owner acceptance remains pending. Recorded issues include 24.76 turnovers/100 possessions and 14.65 shot-clock violations/game; the A1 duration-after-14-second-reset interaction warrants design review. These are diagnostic observations, **not approval to tune parameters**.
- The previously reported T015 commit was `06e080e30bbfb489e5d41cd10fb81550d627f745`. Treat this as a historical checkpoint, **not** a guarantee of current HEAD.
- Amendment 003 (continuation timing): **design/review only unless separately approved**. Do not assume a proposal file exists in every worktree; inspect first.
- **T016–T019 remain unauthorized** until the owner explicitly approves them. No M002 completion/GO claim.

**Important correction:** an older AGENTS.md stated that M002 had zero implementation and that T003 was wholly unapproved. That statement is obsolete. Some frozen `plan.md`/`design-decisions.md` headers still describe their original pre-implementation state; use the later task/evidence record for execution status, without changing the frozen historical text just to make it read as current.

## 4. Architecture and implementation constraints

- `packages/simulation_core/`: pure Dart models, generation, validation, simulation, deterministic PRNG, typed event ledger, replay reducer, derived event accounting, and calibration tests.
- `lib/`: Flutter presentation, navigation, and app-only formatting. Do not place simulation business rules in UI code.
- `test/`: Flutter/widget tests; `packages/simulation_core/test/`: package/unit/property/simulation tests.
- `specs/`: milestone contracts, amendments, experiments, task reports, evidence, and acceptance records.
- Keep core free of Flutter, Flame, databases, network access, and production `dart:io`. A package test may intentionally use `dart:io`; the source-isolation test must still pass.
- M001 uses `xorshift32-v1` via `DeterministicRandom`. Do not use `dart:math Random` or ambient randomness for gameplay.
- One source of truth: events are authoritative; reducer validates them; box scores and derived totals come from event accounting. Never maintain a competing score state.
- M002 game inputs, rules, events, and fingerprints are versioned independently of M001 league snapshots. Keep serializations canonical, deterministic, and explicitly validated.
- M002 has an expressly approved exception for the pure-Dart `package:crypto` dependency used in SHA-256 fingerprinting. Do not reinterpret the old “dependency-free at runtime” M001 rule to remove an approved dependency. **All other new dependencies require approval.**
- The current M002 scope excludes seasons, trading, contracts, coaching AI, tactics, rotations, injuries, saves, networking, and unapproved Flutter feature work.

### Simulation rules: non-negotiable invariants

1. Same input, seed, approved version identifiers, and execution environment-independent canonical rules produce identical serialized ledgers and derived results. Cross-runtime parity (Dart VM/Chrome) matters.
2. PRNG **draw order is an observable contract**. Changing draw count, branch-dependent sampling, coefficients, action timing, event serialization, or canonical fixtures requires impact analysis, appropriate versioning, and explicit owner approval.
3. Do not rebaseline M001 vectors, T012 golden ledgers, historical experiments, or acceptance criteria merely to turn a failure green. Produce a versioned migration/fixture plan if approved behavior changes.
4. Game and shot clocks are integer-valued, monotonic except enumerated legal shot-clock resets, bounded, and governed by frozen horn/shot/foul precedence.
5. Possession, rebound, foul, free-throw, and and-one transitions must be legal, replayable, and typed-error validated. No phantom possessions, shots, turnovers, rebounds, or points.
6. All player/team/period statistics reconcile to the authoritative event ledger; `team.TOV == sum(player.TOV)` under M002's declared simplified attribution rule.
7. No silent time clamping or guaranteed shot opportunity as a shortcut to lower shot-clock violations. Legitimate clock violations must remain possible.
8. Preserve approved A1 phase/action-profile behavior unless an explicit amendment changes it. In particular, the proposed continuation-timing work must evaluate **timing policy separately from offensive action selection**.
9. A simulator that passes structural tests but fails statistical calibration is **not** approved as realistic.

## 5. SDD workflow and scope control

For each task, follow this sequence:

1. **Inventory:** verify branch, clean/dirty status, task ID, baseline, relevant spec and prior evidence; preserve user changes.
2. **Diagnose:** state the observed failure, competing explanations, the minimal evidence needed, and any unknowns. Do not silently alter the hypothesis after seeing results.
3. **Design:** propose the smallest defensible change, deterministic sampling/transition contract, versions/fixture impacts, test plan, statistical plan, and rollback conditions.
4. **Authorization gate:** for design-only or read-only work, stop here. For implementation, require the owner's explicit task-specific GO.
5. **Implement narrowly:** modify only authorized paths and avoid unrelated refactors, new tooling, or speculative optimizations.
6. **Validate:** run the required relevant commands, determinism/ledger audits, regression and calibrated held-out evidence as applicable. Separate tests that prove consistency from tests that measure realism.
7. **Report:** exact changed files, commands and results, versions, seeds, PRNG implications, skipped checks, open risks, and the next gated action.
8. **Git hygiene:** never discard unrelated changes, force-push, merge, tag, or release without permission. Commit/push only when authorized and report actual SHA and destination.

For experiments: pre-register metrics and acceptance thresholds before running cohorts; separate tuning/development seeds from truly held-out evaluation seeds; report effect sizes, uncertainty and multiple-testing adjustments where the approved protocol requires them. **Do not move the goalposts after examining results.**

## 6. OMP + TypeSafe JEV judge policy

**OMP is the coding/review agent.** JEV is a separate *judge* for consequential decisions; it is **not** an automatic second implementation agent and is **not** evidence of gameplay realism. This policy complements the existing global OMP rules; it does not replace them.

### Required effective OMP configuration (verify, do not blindly overwrite)

OMP verified the following effective setup on 2026-10-31. Recheck it before future tasks:

| Role / capability | Expected setting at last checkpoint |
|---|---|
| DEFAULT | `google-antigravity/gemini-3.8-flash` |
| JUDGE | `typesafe/jev-latest` |
| ADVISOR | `opencode-zen/gpt-6.1-sol:auto` |
| COMMIT (observed, not mandated) | `opencode-go/beam-free:auto` |
| TTSR enabled | `true` |
| TTSR judge selection | `auto` |

The effective installed OMP config is authoritative; the COMMIT model is informational, not a Ballgorithm requirement. Check the live environment before citing these as current. The **expected** YAML keys and model-role selectors are documented below. This is a reference to validate against the live config, **not** an instruction to overwrite it:

```yaml
# ~/.omp/agent/config.yml — inspect/merge safely; preserve other keys
modelRoles:
  default: google-antigravity/gemini-3.8-flash
  judge: typesafe/jev-latest
  advisor: opencode-zen/gpt-6.1-sol:auto
ttsr:
  enabled: true
  judge: auto
```

With `ttsr.judge: auto`, OMP runs its applicable *question-rule* judgments only when the resolved judge is a compatible native System One judge (such as the configured TypeSafe JEV). This setting does **not** imply that every task, response, or design was judged.

Expected existing global rules (verify if present):

- `~/.omp/agent/RULES.md`
- `~/.omp/agent/rules/jev-decision-policy.md` (`alwaysApply: true` at last checkpoint)
- `~/.omp/agent/rules/ttsr-unsupported-completion.md`
- `~/.omp/agent/rules/ttsr-unsupported-test-claim.md`
- `~/.omp/agent/rules/ttsr-unsupported-readiness-claim.md`
- `~/.omp/agent/rules/ttsr-unsupported-security-fix.md`
- `~/.omp/agent/rules/ttsr-unsupported-high-impact-conclusion.md`

OMP was observed loading `E:\basketball-manager-sdd\AGENTS.md` when the session was started from that older worktree. This does not prove automatic loading from `E:\ballgorithm-dev`: first place this file at the target worktree root, start a fresh session there, and verify that exact path appears in the loaded context. OMP normally loads the repository-root `AGENTS.md` as session context. Long-lived, always-apply requirements belong in an appropriate `RULES.md`; task subagents may not inherit normal `AGENTS.md` context. Keep global sticky JEV/scope policies in force rather than assuming this file reaches every helper.

`xd://jev_models` previously listed `jev-latest` and `jev-preview`; `xd://jev_judge` previously succeeded. **Do not assume current connectivity, credits, model names, or prices.** Do not save credentials or prepaid-credit details in this repository.

### When to use JEV

First apply the installed global JEV decision policy and its cost limits. For Ballgorithm, a JEV review is **strongly indicated** when an authorized task involves:

- Competing high-impact simulation designs without a decisive local proof (e.g., Amendment 003 continuation timing).
- Fundamental shot-clock, foul/bonus, possession, rebound, and-one, or period-end transition rules.
- Event schema, canonical serialization, fingerprint, PRNG draw order, seed normalization, or version migration.
- An apparent conflict among frozen specifications, tests, causal evidence, and an implementation proposal.
- A contested GO/NO-GO recommendation where the agent's own reasoning should be independently challenged.

A JEV call is generally **unnecessary** for grammar edits, formatting, read-only inventory, straightforward test execution, deterministic repro without ambiguity, or changes already conclusively resolved by approved spec plus proof. Do not invoke JEV merely to appear rigorous or because a document mentions it.

### JEV execution contract

1. Define the exact decision question, options, governing invariants, known evidence, rejected assumptions, and desired verdict **before** calling the judge.
2. Provide only the minimum relevant non-secret material. Do not transmit credentials, private user data, or unrelated source trees.
3. Use the configured automatic TTSR/JEV policy where supported; invoke the judge directly only if the global policy indicates it and the environment permits it.
4. Respect existing credit/cost ceilings and escalation rules. Avoid repetitive judgment loops; escalate unresolved uncertainty to the owner.
5. Record the judge's verdict, key objections, evidence, and any recommendation to reject or revise. A judge recommendation never overrides the constitution, frozen specification, or owner authorization.
6. If JEV is unavailable, returns an unsupported completion, or has inconclusive evidence, **say so**. Never invent a verdict or silently label a task “JEV approved.” Follow the configured unsupported-completion rule and leave consequential decisions pending review.
7. An ADVISOR model may be used under the global policy for a difficult unresolved question; OMP remains the implementer. An ADVISOR role does not authorize changing coding agents or bypassing scope gates.

**Repository policy versus machine config:** this file can prescribe expected behavior, but cannot enable TTSR, install a JEV plugin, select a model, or modify the operator's global `config.yml`. Confirm actual effective configuration in OMP separately. Never modify global agent settings as a side effect of a repository docs task without explicit approval.

## 7. Commands and quality gates

Use commands appropriate to the exact task, platform and workspace. The package requires its **own** analysis; root Flutter analysis does not cover `packages/**`.

```powershell
# Flutter app: repository root
flutter pub get
flutter analyze
flutter test

# Core domain: execute from packages/simulation_core
dart pub get
dart analyze
dart format --set-exit-if-changed lib test
dart test
```

Run Chrome-compatible core tests when the task affects replay, fingerprints, draw order, or canonical serialization; omit/handle the IO-dependent `domain_isolation_test.dart` explicitly and record the command and exclusion. Add relevant seeded stress/paired tests only when the approved task calls for them; do not run massive cohorts reflexively.

Test reporting must distinguish **PASS / FAIL / NOT RUN / BLOCKED**, identify exact tool versions/environments, state whether source was modified during testing, and avoid unverified claims of Android device performance. An older accepted count is a historical baseline, not the current expected number of tests.

### Style and public API expectations

- Follow existing `dart format`, root Flutter lints, package Dart lints, and the surrounding file conventions.
- Prefer immutable `final` models, typed IDs, explicit validation codes, stable canonical JSON, and tests against machine-readable errors rather than message wording.
- Public domain API documentation should describe invariants; UI labels and theme stay in `lib/`.
- Preserve existing widget `ValueKey` contracts and responsive mobile layout behavior when touching presentation code.
- Avoid unnecessary dependencies, code generation, networking, generic abstractions, unrelated formatting, and synthetic pass-only tests.

## 8. Required agent handoff format

Every substantive task ends with a compact report containing:

1. **Task and authorization:** task ID; design-only vs implementation; exact approved scope.
2. **Source checkpoint:** branch, worktree, starting/ending SHA, dirty status.
3. **Evidence:** relevant source/specs reviewed; observed results and unresolved alternative explanations.
4. **Changes:** changed file paths and summary, or explicit `NO FILES CHANGED`.
5. **Verification:** command, platform, outcome, test count/seed/fixture where applicable, skipped checks.
6. **JEV:** invoked / not indicated / unavailable; reason; actual verdict if invoked. Do not imply a judge ran when none did.
7. **Risk and gate:** statistical/behavioral caveats, version/fixture implications, blockers, owner decision needed, and one recommended next action.

**Stop rule:** In the absence of explicit authorization, do not implement Amendment 003, start T016–T019, rewrite frozen acceptance criteria, change coefficients to chase calibration, or pronounce M002 complete. The correct next action may be to return a design for owner review.

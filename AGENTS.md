# AGENTS.md — Ballgorithm

## What Is This Project

Ballgorithm is a **basketball GM simulation game** built in **Godot 4** using **GDScript**.
You play as a General Manager: build a roster, manage the salary cap, run a draft,
simulate an 82-game season, and compete through Play-In and Playoffs. All players are
**100% procedurally generated** — no real NBA players, no real licenses.

This file is the single source of truth for every agent working on this codebase.
Read it fully before writing any code.

---

## Tech Stack

| Layer | Choice |
|---|---|
| Engine | Godot 4.x (stable) |
| Language | GDScript only — no C#, no GDNative |
| UI | Control nodes only — no 3D, no sprites for UI |
| Data Format | Godot Resources (.tres) for persistent data, JSON for generated data if needed |
| Save System | FileAccess + JSON serialization to `user://save.json` |

---

## Folder Structure

```
ballgorithm/
├── AGENTS.md                  ← you are here
├── autoloads/
│   ├── GameState.gd           ← current phase, year, active team
│   ├── LeagueManager.gd       ← all 30 teams, standings, schedule
│   ├── PlayerDB.gd            ← all player records in the league
│   └── CapEngine.gd           ← salary cap rules and calculations
├── resources/
│   ├── Player.gd              ← Player Resource definition
│   └── Team.gd                ← Team Resource definition
├── scenes/
│   ├── MainMenu.tscn
│   ├── NewGame.tscn           ← team name, city, situation picker
│   ├── PreSeasonHub.tscn      ← open-ended hub before draft
│   ├── Draft.tscn
│   ├── FreeAgency.tscn
│   ├── SeasonSim.tscn         ← week-by-week or skip to end
│   ├── PlayIn.tscn
│   ├── Playoffs.tscn
│   └── EndOfSeason.tscn
└── scripts/
    ├── PlayerGenerator.gd     ← procedural player creation
    ├── LeagueGenerator.gd     ← builds 30 teams + rosters
    ├── DraftSystem.gd         ← draft order, AI picks, player logic
    ├── SimEngine.gd           ← game simulation math
    └── ScheduleGenerator.gd   ← 82-game schedule builder
```

**Rules:**
- Scenes go in `scenes/`. Scripts that are NOT attached to a scene go in `scripts/`.
- Autoloads are registered in Project Settings. Do not instantiate them manually.
- Resources (`Player.gd`, `Team.gd`) extend `Resource` and use `@export` only.
- Never put game logic inside a Resource file.

---

## Confirmed Game Loop

This is the **locked, non-negotiable** game loop. Do not add systems outside this loop
without explicit instruction.

```
NEW GAME
  ↓
Pick Team Name + City
  ↓
Pick Team Situation
  [Tanking | Rebuilding | Play-In | Playoff | Contender]
  ↓
LEAGUE GENERATES
  - 29 AI teams generated and balanced
  - Player's roster generated based on their situation
  - Draft order assigned: Tanking = 1st pick, Contender = last
  ↓
PRE-SEASON HUB  (open-ended, player advances manually)
  - View Roster
  - Sign Staff (Coach / Scout / Doctor) — costs budget
  - Upgrade Facilities — costs budget
  - [ADVANCE TO DRAFT] button
  ↓
DRAFT
  - Pick position is determined by situation rank
  - AI teams pick by best player available (by overall rating)
  - [ADVANCE TO FREE AGENCY] button
  ↓
FREE AGENCY
  - Sign available players within cap space
  - AI teams fill roster holes
  - [ADVANCE TO SEASON] button
  ↓
SIMULATE SEASON (82 games)
  - Player chooses: Week by Week OR Skip to End
  - Week by Week: see weekly results, manage roster, advance manually
  - Skip to End: full season simulates instantly, summary screen shown
  ↓
STANDINGS CHECK
  - 1st–6th  → Playoffs directly
  - 7th–10th → Play-In Tournament
  - 11th–15th → Lottery (sets next year's draft order)
  - GameState.playoff_status is one of: "playoffs", "playin", "lottery", "eliminated"
  - "eliminated" is set by PlayIn.gd when a play-in team loses and does not qualify
  ↓
PLAY-IN TOURNAMENT
  - 7 vs 8: winner = 7th seed
  - 9 vs 10: winner plays loser of 7v8
  - Final winner = 8th seed
  ↓
PLAYOFFS (1st–8th seed bracket)
  - Best of 7 per round
  - Simulate or Watch option per series
  ↓
FINALS → CHAMPION CROWNED
  ↓
END OF SEASON
  - Player ages increment
  - Player progression/regression calculated
  - Contracts expire (years decrement)
  - New draft class generated
  - Draft order set by standings (worst → best)
  ↓
BACK TO PRE-SEASON HUB (next year)
```

---

## Data Models

### Player (res://resources/Player.gd)

```gdscript
extends Resource
class_name Player

@export var id: String = ""
@export var full_name: String = ""
@export var age: int = 0
@export var position: String = ""        # PG | SG | SF | PF | C
@export var archetype: String = ""       # see Archetypes section
@export var salary: int = 0             # in dollars (e.g. 5000000)
@export var contract_years: int = 0
@export var potential: int = 0          # 40–99, hidden until scouted
@export var is_potential_revealed: bool = false

# Attribute groups — all values 0–99
@export var physicals: Dictionary = {
    "Speed": 0, "Vertical": 0, "Strength": 0, "Stamina": 0, "Durability": 0
}
@export var skills: Dictionary = {
    "Shooting3": 0, "ShootingMid": 0, "FreeThrow": 0,
    "Finishing": 0, "BallHandling": 0, "Passing": 0, "PostPlay": 0
}
@export var defense: Dictionary = {
    "PerimeterD": 0, "PostD": 0, "Steal": 0, "Block": 0, "DefIQ": 0
}
@export var mental: Dictionary = {
    "OffIQ": 0, "Clutch": 0, "Composure": 0, "Leadership": 0, "WorkEthic": 0
}

# Computed overall — call this, don't store it
func get_overall() -> int:
    var total = 0
    var count = 0
    for group in [physicals, skills, defense, mental]:
        for val in group.values():
            total += val
            count += 1
    return int(total / count) if count > 0 else 0
```

### Team (res://resources/Team.gd)

```gdscript
extends Resource
class_name Team

@export var team_id: String = ""
@export var city: String = ""
@export var name: String = ""
@export var situation: String = ""      # Tanking | Rebuilding | Play-In | Playoff | Contender
@export var is_player_team: bool = false

@export var roster: Array = []          # Array of Player resources
@export var cap_space: int = 0         # remaining cap (starts at salary cap minus contracts)
@export var draft_pick: int = 0        # 1–30, position in draft

@export var wins: int = 0
@export var losses: int = 0

# Staff levels 1–5
@export var staff_coach: int = 1
@export var staff_scout: int = 1
@export var staff_medical: int = 1

# Facility level 1–5
@export var facilities: int = 1

# Budget for pre-season spending
@export var budget: int = 0
```

---

## Key Constants (use these everywhere, never hardcode)

```gdscript
# In GameState.gd or a Constants.gd autoload
const SALARY_CAP: int = 136_000_000       # $136M hard cap for v1
const ROSTER_MIN: int = 13
const ROSTER_MAX: int = 15
const DRAFT_ROUNDS: int = 2
const SEASON_GAMES: int = 82
const TEAMS_PER_CONFERENCE: int = 15
const PLAYOFF_SEEDS: int = 8
const PLAYIN_SEEDS_START: int = 7         # 7th through 10th go to Play-In

const SITUATIONS: Array = [
    "Tanking", "Rebuilding", "Play-In", "Playoff", "Contender"
]

# Draft pick position by situation (1 = first overall)
const SITUATION_DRAFT_ORDER: Dictionary = {
    "Tanking": 1, "Rebuilding": 6, "Play-In": 11, "Playoff": 16, "Contender": 21
}

# Starting cap space by situation
const SITUATION_CAP_SPACE: Dictionary = {
    "Tanking": 100_000_000,
    "Rebuilding": 70_000_000,
    "Play-In": 40_000_000,
    "Playoff": 20_000_000,
    "Contender": 5_000_000
}
```

---

## Player Archetypes

Every generated player is assigned one primary archetype. Archetypes bias attribute
generation — they do not hard-lock stats.

**Offensive Archetypes:**
`Floor General`, `Shot Creator`, `Sharpshooter`, `Slasher`, `Post Scorer`,
`Point Forward`, `Stretch Big`, `Pick-and-Roll Maestro`, `Microwave Scorer`,
`Transition Finisher`

**Defensive Archetypes:**
`Perimeter Stopper`, `Paint Protector`, `Defensive Anchor`,
`Pickpocket`, `Switch Defender`, `Glass Cleaner`, `Hustler`

**Hybrid Archetypes:**
`3-and-D Wing`, `Combo Guard`, `Point Center`, `Stretch Lock`,
`Energy Big`, `Glue Guy`, `Clutch Performer`, `Iso God`

---

## Team Situations — What They Mean In Code

| Situation | Roster Quality | Draft Pick | Cap Space | Starting Budget |
|---|---|---|---|---|
| Tanking | OVR 45–58 | 1–5 | $100M | $15M |
| Rebuilding | OVR 55–65 | 6–10 | $70M | $10M |
| Play-In | OVR 63–72 | 11–15 | $40M | $7M |
| Playoff | OVR 70–78 | 16–20 | $20M | $5M |
| Contender | OVR 75–85 | 21–30 | $5M | $3M |

Roster quality means the **average overall** of the 13 generated players for that team.

---

## SimEngine Rules (v1 — keep it simple)

Season simulation must be deterministic given the same seed. Core formula:

```
team_strength = average OVR of top 8 players on roster
coach_bonus = staff_coach * 2          # max +10
facility_bonus = facilities * 1        # max +5

effective_strength = team_strength + coach_bonus + facility_bonus

win_probability = effective_strength_home / (effective_strength_home + effective_strength_away)
win_probability += 0.03                # home court advantage

result = randf() < win_probability → home team wins
```

For week-by-week sim: simulate 7 days of games, return results array, update standings.
For skip-to-end: loop all 82 game slots, same logic, return final standings.

Injuries: 3% chance per game per player. Injured players are excluded from
`effective_strength` calculation for that game. Injury duration: `randi_range(3, 21)` days.

---

## Coding Standards

### Naming
- Classes: `PascalCase` — `PlayerGenerator`, `SimEngine`
- Variables/functions: `snake_case` — `get_overall()`, `cap_space`
- Constants: `ALL_CAPS_SNAKE` — `SALARY_CAP`, `ROSTER_MAX`
- Signals: `snake_case` past tense — `player_signed`, `season_simulated`

### GDScript Style
```gdscript
# Good — typed, explicit
func generate_player(position: String, situation: String) -> Player:
    var player = Player.new()
    player.position = position
    return player

# Bad — untyped, ambiguous
func gen(pos, sit):
    var p = Player.new()
    return p
```

- Always type function parameters and return types.
- Always type variable declarations where possible: `var score: int = 0`
- Use `@export` only in Resource files. Never in scene scripts.
- Emit signals for state changes. Do not call scene methods directly across scenes.
- Autoloads communicate via signals or return values. Never reach into a scene node from an autoload.
- UI must always read cap data via `CapEngine.get_cap_summary(team)`. Never read `team.cap_space` directly in scene scripts.

### Scene ↔ Script Rules
- Every scene has exactly one root script attached.
- Scene scripts `_ready()` connects to autoload signals, never the reverse.
- Pass data between scenes via `GameState` autoload, not scene references.

### No Premature Systems
Do not implement these until explicitly instructed:
- Media / press conference system
- Fan engagement / social media feed
- Sponsorships / revenue streams
- Player personalities / locker room drama
- Online multiplayer
- Historical scenarios / challenge mode

---

## GameState — Phase Tracking

`GameState.gd` is the single source of truth for where in the loop the game is.

```gdscript
enum Phase {
    MAIN_MENU,
    NEW_GAME,
    LEAGUE_GENERATING,
    PRE_SEASON_HUB,
    DRAFT,
    FREE_AGENCY,
    SEASON_SIM,
    PLAY_IN,
    PLAYOFFS,
    FINALS,
    END_OF_SEASON
}

var current_phase: Phase = Phase.MAIN_MENU
var current_year: int = 1
var player_team_id: String = ""
var sim_mode: String = "week"           # "week" | "skip"
```

Changing phase: always go through `GameState.set_phase(new_phase)` which emits
`phase_changed(new_phase)` so all scenes can react.

---

## Save / Load

Save everything through `GameState.save_game()` and `GameState.load_game()`.
Format: JSON serialized to `user://save.json`.

Serialization rule: Resources serialize to dictionaries. Implement `to_dict()` and
`from_dict(data: Dictionary)` on `Player` and `Team`.

---

## What To Build — In Order

Work on these steps sequentially. Do not start step N+1 until step N is complete and reviewed.

```
✅ Step 1  → Player.gd + Team.gd (Resource definitions)
✅ Step 2  → PlayerGenerator.gd (procedural player creation)
✅ Step 3  → LeagueGenerator.gd (30 teams, rosters by situation)
✅ Step 4  → CapEngine.gd (cap space tracking, salary validation)
✅ Step 5  → GameState.gd (phase enum, team reference, year)
✅ Step 6  → MainMenu.tscn + NewGame.tscn (team name, city, situation picker)
✅ Step 7  → LeagueManager.gd (standings, schedule shell)
✅ Step 8  → PreSeasonHub.tscn (roster view, staff/facility upgrade UI)
✅ Step 9  → DraftSystem.gd + Draft.tscn
✅ Step 10 → FreeAgency.tscn
✅ Step 11 → ScheduleGenerator.gd + SimEngine.gd
✅ Step 12 → SeasonSim.tscn (week-by-week and skip-to-end modes)
✅ Step 13 → PlayIn.tscn
✅ Step 14 → Playoffs.tscn + Finals resolution
✅ Step 15 → EndOfSeason.tscn (progression, aging, contract expiry)
✅ Step 16 → Save/Load system
✅ Step 17 → Full loop test (New Game → Champion → Year 2)
```

Step 17 note: update `Draft.gd` `_initialize_draft()` to check if
`GameState.draft_pool_next` is non-empty. If so, use it as the draft pool instead of
calling `DraftSystem.build_draft_pool()`. After consuming it, clear
`GameState.draft_pool_next`.

---

## Agent Behavior Rules

1. **One step at a time.** Complete the current step. Do not jump ahead.
2. **Ask before inventing.** If a system isn't described here, ask before building it.
3. **No placeholder logic.** Do not write `pass` or `TODO` without flagging it explicitly.
4. **Test assumptions.** If a formula or rule seems wrong, flag it — don't silently change it.
5. **Minimal dependencies.** Each script should do one thing. Don't merge SimEngine and ScheduleGenerator.
6. **No UI polish yet.** Functionality before aesthetics. Placeholder buttons and labels are fine.
7. **Comment non-obvious logic.** Especially in SimEngine and PlayerGenerator.
8. **Signal over coupling.** If two systems need to talk, use signals. Don't hold direct references to scenes.

---

## Phase 2 — Polish & Depth

```
P01 → Player scouting system (reveal potential via scout level)
P02 → Mid-season trades (player-for-player, with cap validation)
P03 → Injury system visible in UI (injured players flagged in roster views)
P04 → Player morale / locker room (Leadership + Composure affect team performance)
P05 → Season awards (MVP, DPOY, ROY, All-League teams)
P06 → Historical records (track champions, MVPs per year)
P07 → AI free agency (AI teams sign from free agent pool, not just draft)
P08 → Contract extensions (re-sign your own players before they hit FA)
P09 → Better sim feedback (box scores, player stat lines per game)
P10 → Visual polish (team colors, consistent UI theme, fonts)
P11 → Staff serialization cleanup (use StaffMember.from_dict when staff objects need reconstruction; remove fallback StaffMember generation in UI refresh)
```

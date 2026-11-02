# Amendment 001 — Horizontal scrolling clarification

> **Status:** **FROZEN — authorised 2026-11-02** under `BALLGORITHM — M003 T025 MOBILE UX VERIFICATION`.
> **Applies to:** `specs/003-mobile-game-day/spec.md` (frozen 2026-11-02) and its acceptance criteria.
> **Scope:** layout clarification only. No data-integrity, determinism, navigation or simulation
> requirement is changed.

## 1. Authorisation

The owner authorised "a documentation clarification distinguishing page-level horizontal scrolling from
permitted horizontal scrolling inside player box-score tables" as part of the T025 verification task.
Nothing else in the frozen specification is rewritten.

## 2. Clarified rule

| Level | Requirement |
|---|---|
| Page | Every screen must fit the portrait width without page-level horizontal scrolling and without `RenderFlex`/paint overflow. |
| Player box-score tables | May scroll horizontally, independently of the page, because twelve statistic columns plus a full player name exceed any phone width. |
| Player names | Must remain complete in the data and must not be forced into ellipsis or a fixed-width box. Long names may extend the table's scrollable width. |
| Period table and team statistics | Must remain readable without horizontal scrolling. |
| Navigation and data | Unchanged: all values still come from the single `GameResult`; no statistic is recomputed. |

## 3. What this does not change

- It does not relax AC-MGD-08's requirement that screens fit at 360×640, 393×852 and 430×932 without
  overflow.
- It does not allow a horizontally scrolling page, a clipped score, seed, label or action, or a hidden
  control.
- It does not affect any simulation contract, version, fixture or M002 evidence.

## 4. Evidence obligation

T025's mobile layout tests assert, per width:

1. no framework overflow exception anywhere in the flow;
2. exactly two horizontal scroll views exist on a result screen, and both are ancestors of the player
   tables;
3. dragging a player table horizontally does not move the page's vertical scroll position or the
   page-level layout;
4. a long-name fixture keeps the full name text with `Text.overflow == null`.

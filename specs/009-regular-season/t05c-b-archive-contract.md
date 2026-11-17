# M009-T05C-B — Per-Season Historical Archive Contract Specification

**Status:** Specification for `M009-T05C-B` (no archive file writing implemented in `T05C-A`).

## 1. Per-Slot and Per-Year Archive Identity

- Each archived season is uniquely identified by `(slot, seasonId, seasonYear)` where `seasonId == '${careerId}-season-$seasonYear'`.
- `SeasonHistoryRecord.archiveId` is deterministic: `'${seasonId}-archive'`.
- On file-backed storage, the archive path is isolated per slot and year:
  - Default slot: `ballgorithm_gm_career_archive_y<seasonYear>.json`
  - Named slot `<slot>`: `ballgorithm_gm_career_<slot>_archive_y<seasonYear>.json`

## 2. Canonical Archive Content & Digest

- An archive payload contains the immutable, canonical JSON of the completed season's full `regularSeasonState`, `playInState`, and `playoffState` (including all 1,230+ game results, box scores, `inputEvidence`, `inputFingerprint`s, and `gameInputSnapshots`), wrapped with `archiveSchemaVersion`, `careerId`, `seasonId`, `seasonYear`, and `archiveId`.
- `SeasonHistoryRecord.archiveDigest` MUST equal the lowercase 64-character hex SHA-256 of the UTF-8 bytes of that exact canonical archive JSON string.
- Fake or placeholder digests are forbidden; `archiveDigest` is computed exclusively from the exact serialized archive bytes.

## 3. Immutable Write & Atomic Active-Save Coordination

- Transitioning Year $N \to N+1$ MUST follow strict write-before-publish ordering:
  1. Serialize and digest the Year $N$ archive payload.
  2. Write the Year $N$ archive via `.tmp` + `flush: true` + atomic promote **before** writing the Year $N+1$ active career save.
  3. If an archive file already exists for `(slot, seasonYear)`:
     - Verify its content SHA-256 matches the expected `archiveDigest`.
     - If it matches, treat as idempotent and reuse; if it differs, fail without overwriting.
  4. Write the Year $N+1$ active career save via `.tmp` + `.bak` + atomic promote.
  5. Publish the Year $N+1$ `GmCareer` in memory only after both writes succeed.

## 4. Missing, Corrupt, and Orphan Archive Handling

- **Missing or corrupt archive:** Any attempt to inspect detailed historical games for an archived `SeasonHistoryRecord` MUST verify `sha256(utf8.encode(archiveJson)) == record.archiveDigest` and validate the decoded `RegularSeasonState`/`PlayInState`/`PlayoffState`. If the file is missing, empty, or fails digest/validation, throw a typed storage/format exception. The UI/domain MUST NEVER silently pretend detailed history exists.
- **Orphan archive recovery:** If a crash occurs after writing the Year $N$ archive but before promoting the Year $N+1$ active save, the active save still points to completed Year $N$ (with `seasonHistory` not yet containing Year $N$). On restart, Year $N$ remains intact and playable/transitionable; a subsequent transition either verifies and reuses the matching orphan archive or fails safely on digest mismatch.
- **Backup restoration consistency:** Restoring `.bak` for the active save rolls back only the active career; any already-written Year $N$ archive remains immutable and unreferenced until the transition is retried. Clearing a slot (`storage.clear(slot: slot)`) deletes the active save, `.bak`, `.tmp`, and all per-year archive files for that slot only.

## 5. Web-Compatible Storage & Save Export / Transfer

- `GmCareerStorage` (or a dedicated `GmCareerArchiveStorage` interface) MUST abstract archive read/write/hasArchive/clear by `(slot, seasonYear)` so `InMemoryGmCareerStorage`, `FileGmCareerStorage`, and future Web/IndexedDB implementations share identical semantics.
- Save export / bundle transfer MUST package the active career JSON together with all referenced `(seasonYear -> archiveJson)` payloads and verify every `SeasonHistoryRecord.archiveDigest` on import.

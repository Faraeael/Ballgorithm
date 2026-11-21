import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/league.dart';
import '../models/roster_category.dart';
import 'career_phase.dart';
import 'gm_career.dart';
import 'play_in_state.dart';
import 'playoff_state.dart';
import 'regular_season_game_input_evidence.dart';
import 'regular_season_state.dart';
import 'rollover_validation_proof.dart';
import 'season_history_record.dart';

/// Immutable, complete per-season historical archive payload.
///
/// Preserves the full regular-season, Play-In, and playoff ledgers, box scores,
/// game-time league snapshots, input evidence, and fingerprints for one
/// completed season.
final class SeasonArchive {
  SeasonArchive({
    this.archiveSchemaVersion = currentArchiveSchemaVersion,
    required this.careerId,
    required this.seasonId,
    required this.seasonYear,
    required this.archiveId,
    required this.regularSeasonState,
    required this.playInState,
    required this.playoffState,
  }) {
    validate();
  }

  /// Extracts a verified [SeasonArchive] from a completed [GmCareer] season.
  factory SeasonArchive.fromCareer(GmCareer career) {
    career.validate();
    final rs = career.regularSeasonState;
    final pi = career.playInState;
    final po = career.playoffState;
    if (career.phase != CareerPhase.playoffs ||
        rs == null ||
        pi == null ||
        po == null ||
        !pi.isComplete ||
        !po.isComplete) {
      throw StateError('Cannot archive season before championship completion');
    }
    return SeasonArchive(
      careerId: career.id,
      seasonId: rs.seasonId,
      seasonYear: career.currentYear,
      archiveId: archiveIdFor(rs.seasonId),
      regularSeasonState: rs,
      playInState: pi,
      playoffState: po,
    );
  }

  static const int currentArchiveSchemaVersion = 1;

  static String archiveIdFor(String seasonId) => '$seasonId-archive';

  final int archiveSchemaVersion;
  final String careerId;
  final String seasonId;
  final int seasonYear;
  final String archiveId;
  final RegularSeasonState regularSeasonState;
  final PlayInState playInState;
  final PlayoffState playoffState;

  void validate() {
    if (archiveSchemaVersion != currentArchiveSchemaVersion) {
      throw FormatException(
        'Unsupported season archive schema version: $archiveSchemaVersion',
      );
    }
    if (careerId.trim().isEmpty ||
        seasonYear < 1 ||
        seasonId != RegularSeasonState.seasonIdFor(careerId, seasonYear) ||
        archiveId != archiveIdFor(seasonId)) {
      throw const FormatException('Invalid SeasonArchive identity');
    }
    regularSeasonState.validate();
    final schedule = regularSeasonState.schedule;
    if (schedule == null ||
        regularSeasonState.seasonId != seasonId ||
        regularSeasonState.seasonYear != seasonYear ||
        regularSeasonState.completedRounds != 82 ||
        regularSeasonState.completedGames != 1230 ||
        regularSeasonState.gameResults.length != 1230 ||
        schedule.totalFixtures != 1230) {
      throw const FormatException(
        'SeasonArchive requires a completed 1,230-game regular season',
      );
    }
    _validateRegularSeasonEvidence(regularSeasonState);
    if (!playInState.isComplete ||
        playInState.seasonId != seasonId ||
        playInState.seasonYear != seasonYear) {
      throw const FormatException(
        'SeasonArchive requires a completed Play-In state',
      );
    }
    playInState.validate(regularSeasonState: regularSeasonState);
    if (!playoffState.isComplete ||
        playoffState.champion == null ||
        playoffState.seasonId != seasonId ||
        playoffState.seasonYear != seasonYear) {
      throw const FormatException(
        'SeasonArchive requires a completed playoff championship',
      );
    }
    playoffState.validate(
      regularSeason: regularSeasonState,
      playIn: playInState,
    );
  }

  /// Derives the compact [SeasonHistoryRecord] summary bound to [archiveDigest].
  SeasonHistoryRecord toHistoryRecord(String archiveDigest) {
    validate();
    return _buildHistoryRecord(archiveDigest);
  }

  /// Package-internal derivation reusing a [RolloverValidationProof].
  SeasonHistoryRecord toHistoryRecordWithProof(
    String archiveDigest,
    RolloverValidationProof proof,
  ) {
    if (!identical(proof.archive, this)) {
      throw StateError('RolloverValidationProof does not match this archive');
    }
    return _buildHistoryRecord(archiveDigest);
  }

  SeasonHistoryRecord _buildHistoryRecord(String archiveDigest) {
    final ranked = PlayInRanking.rank(regularSeasonState);
    final table = regularSeasonState.standings.table;
    final standings = [
      for (var i = 0; i < ranked.length; i++)
        SeasonStandingSummary(
          rank: i + 1,
          teamId: ranked[i],
          wins: table[ranked[i].value]!.wins,
          losses: table[ranked[i].value]!.losses,
        ),
    ];
    final g1 = playInState.gameResults['$seasonId-playin-g1']!;
    final g2 = playInState.gameResults['$seasonId-playin-g2']!;
    final g3 = playInState.gameResults['$seasonId-playin-g3']!;
    final playInOutcome = PlayInOutcomeSummary(
      game1WinnerTeamId: g1.summary.winnerTeamId,
      game2WinnerTeamId: g2.summary.winnerTeamId,
      game3WinnerTeamId: g3.summary.winnerTeamId,
      seed15TeamId: g1.summary.winnerTeamId,
      seed16TeamId: g3.summary.winnerTeamId,
    );
    final playoffSeries = <PlayoffSeriesSummary>[];
    for (var i = 0; i < 15; i++) {
      final slot = playoffState.seriesAt(i);
      final first = slot.firstTeamId!;
      final second = slot.secondTeamId!;
      playoffSeries.add(
        PlayoffSeriesSummary(
          seriesIndex: i,
          round: slot.round,
          firstTeamId: first,
          secondTeamId: second,
          winnerTeamId: playoffState.seriesWinner(i)!,
          firstTeamWins: playoffState.seriesWins(i, first),
          secondTeamWins: playoffState.seriesWins(i, second),
        ),
      );
    }
    return SeasonHistoryRecord(
      seasonYear: seasonYear,
      seasonId: seasonId,
      championTeamId: playoffState.champion!,
      regularSeasonStandings: standings,
      playInOutcome: playInOutcome,
      playoffSeries: playoffSeries,
      archiveId: archiveId,
      archiveDigest: archiveDigest,
    );
  }

  Map<String, Object?> toJson() => {
    'archiveSchemaVersion': archiveSchemaVersion,
    'careerId': careerId,
    'seasonId': seasonId,
    'seasonYear': seasonYear,
    'archiveId': archiveId,
    'regularSeasonState': _sortStateKeyedMaps(regularSeasonState.toJson()),
    'playInState': _sortStateKeyedMaps(playInState.toJson()),
    'playoffState': _sortStateKeyedMaps(playoffState.toJson()),
  };

  static Map<String, Object?> _sortStateKeyedMaps(
    Map<String, Object?> stateJson,
  ) {
    const unorderedMapKeys = {
      'gameIdentities',
      'gameResults',
      'gameInputSnapshots',
    };
    return {
      for (final entry in stateJson.entries)
        entry.key: unorderedMapKeys.contains(entry.key) && entry.value is Map
            ? _sortedStringKeyMap(entry.value! as Map)
            : entry.value,
    };
  }

  static Map<String, Object?> _sortedStringKeyMap(Map<dynamic, dynamic> map) {
    final keys = [for (final k in map.keys) k as String]..sort();
    return {for (final k in keys) k: map[k]};
  }

  static void _validateRegularSeasonEvidence(RegularSeasonState state) {
    final schedule = state.schedule!;
    final fixturesById = {
      for (final fixture in schedule.allFixtures) fixture.id: fixture,
    };
    final openingTeamIds = {
      for (final team in state.openingTeams) team.teamId.value,
    };
    final historicalLeagues = <String, League>{};
    for (final entry in state.gameResults.entries) {
      final fixture = fixturesById[entry.key]!;
      final result = entry.value;
      final evidence = result.inputEvidence;
      if (evidence == null ||
          result.fingerprintVersion == null ||
          result.coreEngineVersion == null ||
          result.leagueSchemaVersion == null) {
        throw const FormatException(
          'Archived regular-season result lacks historical input evidence',
        );
      }
      final snapshotJson = state.gameInputSnapshots[evidence.leagueSnapshotId];
      if (snapshotJson == null) {
        throw const FormatException(
          'Archived game-time league snapshot is missing',
        );
      }
      final historicalLeague = historicalLeagues.putIfAbsent(
        evidence.leagueSnapshotId,
        () => RegularSeasonGameInputEvidence.parseLeagueSnapshot(
          snapshotId: evidence.leagueSnapshotId,
          leagueSnapshotJson: snapshotJson,
          openingTeamIds: openingTeamIds,
        ),
      );
      final historicalInput = evidence.validate(
        leagueSnapshotId: evidence.leagueSnapshotId,
        leagueSnapshotJson: snapshotJson,
        league: historicalLeague,
        inputFingerprint: result.inputFingerprint,
        homeTeamId: result.homeTeamId.value,
        awayTeamId: result.awayTeamId.value,
        gameSeed: result.gameSeed,
        simulationVersion: result.simulationVersion,
        rulesVersion: result.rulesVersion,
        eventSchemaVersion: result.eventSchemaVersion,
        prngImplementationId: result.prngImplementationId,
        fingerprintVersion: result.fingerprintVersion!,
        coreEngineVersion: result.coreEngineVersion!,
        leagueSchemaVersion: result.leagueSchemaVersion!,
      );
      final participants = {fixture.homeTeamId.value, fixture.awayTeamId.value};
      final standardPlayers = <String>{};
      final playerTeams = <String, String>{};
      for (final team in historicalInput.league.teams) {
        if (!participants.contains(team.id.value)) continue;
        for (final player in team.players) {
          if (team.roster.categoryOf(player.id) == RosterCategory.standard) {
            standardPlayers.add(player.id.value);
            playerTeams[player.id.value] = team.id.value;
          }
        }
      }
      result.validateFor(
        fixture: fixture,
        expectedSeasonId: state.seasonId,
        expectedSeasonYear: state.seasonYear,
        standardPlayers: standardPlayers,
        playerTeams: playerTeams,
      );
    }
  }
}

/// Canonical serialization and SHA-256 verification for [SeasonArchive].
final class SeasonArchiveCodec {
  const SeasonArchiveCodec._();

  /// Encodes [archive] into canonical JSON and computes its SHA-256 digest.
  static ({String json, String digest}) encodeWithDigest(
    SeasonArchive archive,
  ) {
    archive.validate();
    return _encodeWithDigestUnchecked(archive);
  }

  /// Package-internal encoding reusing a [RolloverValidationProof].
  static ({String json, String digest}) encodeWithDigestWithProof(
    SeasonArchive archive,
    RolloverValidationProof proof,
  ) {
    if (!identical(proof.archive, archive)) {
      throw StateError('RolloverValidationProof does not match this archive');
    }
    return _encodeWithDigestUnchecked(archive);
  }

  static ({String json, String digest}) _encodeWithDigestUnchecked(
    SeasonArchive archive,
  ) {
    final encoded = jsonEncode(archive.toJson());
    final digest = digestOf(encoded);
    return (json: encoded, digest: digest);
  }

  /// Computes the lowercase 64-char hex SHA-256 digest of [archiveJson] UTF-8.
  static String digestOf(String archiveJson) =>
      sha256.convert(utf8.encode(archiveJson)).toString();

  /// Verifies [expectedDigest] and decodes/validates the full [SeasonArchive].
  static SeasonArchive decodeAndVerify(
    String archiveJson, {
    required String expectedDigest,
    String? expectedCareerId,
    int? expectedSeasonYear,
    SeasonHistoryRecord? expectedRecord,
  }) {
    if (archiveJson.trim().isEmpty) {
      throw const FormatException('Season archive JSON is empty');
    }
    final actualDigest = digestOf(archiveJson);
    if (actualDigest != expectedDigest) {
      throw FormatException(
        'Season archive digest mismatch: expected $expectedDigest, got $actualDigest',
      );
    }
    final Object? raw;
    try {
      raw = jsonDecode(archiveJson);
    } catch (e) {
      throw FormatException('Malformed SeasonArchive JSON: $e');
    }
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('Invalid SeasonArchive JSON: expected Map');
    }
    final archiveSchemaVersion = raw['archiveSchemaVersion'];
    final careerId = raw['careerId'];
    final seasonId = raw['seasonId'];
    final seasonYear = raw['seasonYear'];
    final archiveId = raw['archiveId'];
    final rawRs = raw['regularSeasonState'];
    final rawPi = raw['playInState'];
    final rawPo = raw['playoffState'];
    if (archiveSchemaVersion is! int ||
        careerId is! String ||
        seasonId is! String ||
        seasonYear is! int ||
        archiveId is! String ||
        rawRs is! Map<String, dynamic> ||
        rawPi is! Map<String, dynamic> ||
        rawPo is! Map<String, dynamic>) {
      throw const FormatException('Malformed SeasonArchive payload');
    }
    if (expectedCareerId != null && careerId != expectedCareerId) {
      throw FormatException(
        'SeasonArchive careerId mismatch: expected $expectedCareerId, got $careerId',
      );
    }
    if (expectedSeasonYear != null && seasonYear != expectedSeasonYear) {
      throw FormatException(
        'SeasonArchive seasonYear mismatch: expected $expectedSeasonYear, got $seasonYear',
      );
    }
    final archive = SeasonArchive(
      archiveSchemaVersion: archiveSchemaVersion,
      careerId: careerId,
      seasonId: seasonId,
      seasonYear: seasonYear,
      archiveId: archiveId,
      regularSeasonState: RegularSeasonState.fromJson(rawRs, schemaVersion: 21),
      playInState: PlayInState.fromJson(rawPi),
      playoffState: PlayoffState.fromJson(rawPo),
    );
    if (expectedRecord != null) {
      if (expectedRecord.archiveDigest != expectedDigest) {
        throw const FormatException(
          'SeasonHistoryRecord archiveDigest mismatch',
        );
      }
      final derived = archive.toHistoryRecord(expectedDigest);
      if (derived != expectedRecord) {
        throw const FormatException(
          'SeasonArchive summary does not match SeasonHistoryRecord',
        );
      }
    }
    return archive;
  }
}

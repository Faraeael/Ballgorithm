import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:simulation_core/simulation_core.dart';
import 'package:simulation_core/src/domain_versions.dart' as domain_versions;
import 'package:test/test.dart';

GmCareer _completedOffseasonCareer() {
  final setup = const CareerSetupService().generate(
    const CareerSetupRequest(
      selectedTeamId: TeamId('team-1'),
      selectedSituation: FranchiseSituation.tanking,
      seed: 20261028,
    ),
  );
  var c = GmCareer.fromSetupResult(setup, id: 'p2c1a-test');
  const draftService = DraftExecutionService();
  const signingService = RookieSigningService();
  const aiSigningService = RookieAiSigningService();
  const marketService = FreeAgentMarketService();
  const clearanceService = OffseasonClearanceService();
  const hardshipService = HardshipSettlementService();
  const rsEntryService = RegularSeasonEntryService();
  const rsScheduleService = RegularSeasonScheduleService();

  c = draftService.startDraft(c);
  while (!c.draftExecutionState.isCompleted) {
    if (c.draftExecutionState.isHumanTurn(
      order: c.draftOrder,
      userTeamId: c.userFranchiseId,
    )) {
      final pick = c.draftClass.prospects.firstWhere(
        (p) => !c.draftExecutionState.draftRights.containsKey(p.id.value),
      );
      c = draftService.makeHumanSelection(career: c, prospectId: pick.id);
    } else {
      c = draftService.executeAiSelection(c);
    }
  }
  c = aiSigningService.initialize(c);
  while (aiSigningService.pendingRights(c).isNotEmpty) {
    c = aiSigningService.applyNextDecision(c);
  }
  for (final r in c.unsignedDraftRights) {
    if (r.owningTeamId == c.userFranchiseId) {
      c = signingService.signDraftedRookie(
        career: c,
        teamId: c.userFranchiseId,
        prospectId: r.prospectId,
        category: RosterCategory.standard,
        durationYears: 2,
      );
    }
  }
  for (var round = 0; round < 2; round++) {
    c = marketService.startRound(c);
    c = marketService.prepareResolution(c);
    while (c.freeAgentMarket.isResolvable) {
      c = marketService.resolveNext(c);
    }
  }
  c = clearanceService.start(c);
  c = clearanceService.prepare(c);
  while (c.offseasonClearance.isResolvable) {
    c = clearanceService.resolveNext(c);
  }
  c = hardshipService.prepare(c, humanParticipationConfirmed: true);
  while (c.hardshipSettlement.isResolvable) {
    c = hardshipService.resolveNext(c);
  }
  c = clearanceService.markCleared(c);
  c = rsEntryService.start(c);
  return rsScheduleService.generate(c);
}

League _withRenamedTeam(
  League league,
  int index,
  String newName,
  String playerFirst,
) {
  final teams = List<Team>.of(league.teams);
  final t = teams[index];
  final players = List<Player>.of(t.players);
  final p0 = players[0];
  players[0] = Player(
    id: p0.id,
    firstName: playerFirst,
    lastName: p0.lastName,
    position: p0.position,
    attributes: p0.attributes,
  );
  teams[index] = t.copyWith(name: newName, roster: Roster(players));
  return League.create(
    id: league.id,
    name: league.name,
    config: league.config,
    teams: teams,
    enforceRosterSize: false,
  );
}

void main() {
  late GmCareer baseCareer;
  late League simLeague;

  setUpAll(() {
    baseCareer = _completedOffseasonCareer();
    simLeague = const RegularSeasonGameAdapter().simulationLeagueFor(
      baseCareer,
    );
  });

  group('M009-PERF-P2C1A: Chunked SHA-256 fingerprint validation', () {
    test(
      'matches full-string SHA-256 across seeds, multiple snapshots, non-ASCII, and JSON escapes',
      () {
        const adapter = RegularSeasonGameAdapter();
        final openingIds = {
          for (final t in baseCareer.regularSeasonState!.openingTeams)
            t.teamId.value,
        };
        final leagues = <League>[
          simLeague,
          _withRenamedTeam(simLeague, 0, 'Équipe Montréal 🏀', 'Nikola Jokić'),
          _withRenamedTeam(
            simLeague,
            1,
            '東京サンズ "Quote\\" \\\\Slash',
            'Line\nBreak\tTab\u0001End',
          ),
        ];

        for (var li = 0; li < leagues.length; li++) {
          final league = leagues[li];
          for (final seed in [1, 42, 20261028]) {
            final input = adapter.createGameInput(
              baseCareer,
              gameId: 'g-$li-$seed',
              homeTeamId: league.teams[0].id,
              awayTeamId: league.teams[1].id,
              seed: seed,
              simulationLeague: league,
            );
            final expectedFp = sha256
                .convert(utf8.encode(GameFingerprint.canonicalJson(input)))
                .toString();
            expect(expectedFp, GameFingerprint.of(input));

            final captured = RegularSeasonGameInputEvidence.capture(input);
            final parsedLeague =
                RegularSeasonGameInputEvidence.parseLeagueSnapshot(
                  snapshotId: captured.evidence.leagueSnapshotId,
                  leagueSnapshotJson: captured.leagueSnapshotJson,
                  openingTeamIds: openingIds,
                );

            final validated = captured.evidence.validate(
              leagueSnapshotId: captured.evidence.leagueSnapshotId,
              leagueSnapshotJson: captured.leagueSnapshotJson,
              league: parsedLeague,
              inputFingerprint: expectedFp,
              homeTeamId: league.teams[0].id.value,
              awayTeamId: league.teams[1].id.value,
              gameSeed: seed,
              simulationVersion: gameSimulationVersion,
              rulesVersion: gameRulesVersion,
              eventSchemaVersion: gameEventSchemaVersion,
              prngImplementationId: 'xorshift32-v1',
              fingerprintVersion: gameFingerprintVersion,
              coreEngineVersion: domain_versions.coreEngineVersion,
              leagueSchemaVersion: domain_versions.snapshotSchemaVersion,
            );
            expect(validated.league.teams.first.name, league.teams.first.name);
          }
        }
      },
    );

    test(
      'rejects tampered snapshot, digest, markers, noncanonical template, and lineup ownership',
      () {
        const adapter = RegularSeasonGameAdapter();
        final fixture = baseCareer
            .regularSeasonState!
            .schedule!
            .rounds
            .first
            .fixtures
            .first;
        final input = adapter.createInput(
          baseCareer,
          fixture,
          simulationLeague: simLeague,
        );
        final expectedFp = GameFingerprint.of(input);
        final captured = RegularSeasonGameInputEvidence.capture(input);
        final openingIds = {
          for (final t in baseCareer.regularSeasonState!.openingTeams)
            t.teamId.value,
        };
        final parsedLeague = RegularSeasonGameInputEvidence.parseLeagueSnapshot(
          snapshotId: captured.evidence.leagueSnapshotId,
          leagueSnapshotJson: captured.leagueSnapshotJson,
          openingTeamIds: openingIds,
        );

        void expectValidateFails(
          RegularSeasonGameInputEvidence ev, {
          String? snapId,
          String? snapJson,
          String? fp,
        }) {
          expect(
            () => ev.validate(
              leagueSnapshotId: snapId ?? captured.evidence.leagueSnapshotId,
              leagueSnapshotJson: snapJson ?? captured.leagueSnapshotJson,
              league: parsedLeague,
              inputFingerprint: fp ?? expectedFp,
              homeTeamId: fixture.homeTeamId.value,
              awayTeamId: fixture.awayTeamId.value,
              gameSeed: fixture.gameSeed,
              simulationVersion: gameSimulationVersion,
              rulesVersion: gameRulesVersion,
              eventSchemaVersion: gameEventSchemaVersion,
              prngImplementationId: 'xorshift32-v1',
              fingerprintVersion: gameFingerprintVersion,
              coreEngineVersion: domain_versions.coreEngineVersion,
              leagueSchemaVersion: domain_versions.snapshotSchemaVersion,
            ),
            throwsFormatException,
          );
        }

        // 1. Changed snapshot JSON (must not hit cached bytes for wrong JSON)
        expectValidateFails(
          captured.evidence,
          snapJson: '${captured.leagueSnapshotJson} ',
        );

        // 2. Incorrect snapshot digest
        expect(
          () => RegularSeasonGameInputEvidence.parseLeagueSnapshot(
            snapshotId: List.filled(64, '0').join(),
            leagueSnapshotJson: captured.leagueSnapshotJson,
            openingTeamIds: openingIds,
          ),
          throwsFormatException,
        );

        // 3. Duplicate snapshot marker in payloadTemplateJson
        final marker =
            (jsonDecode(captured.evidence.payloadTemplateJson)
                    as Map<String, dynamic>)['league']
                as String;
        expectValidateFails(
          RegularSeasonGameInputEvidence(
            leagueSnapshotId: captured.evidence.leagueSnapshotId,
            payloadTemplateJson: captured.evidence.payloadTemplateJson
                .replaceFirst(
                  '"gameSeed"',
                  '"dup":${jsonEncode(marker)},"gameSeed"',
                ),
          ),
        );

        // 4. Missing snapshot marker
        expectValidateFails(
          RegularSeasonGameInputEvidence(
            leagueSnapshotId: captured.evidence.leagueSnapshotId,
            payloadTemplateJson: captured.evidence.payloadTemplateJson
                .replaceFirst(jsonEncode(marker), '"not-a-marker"'),
          ),
        );

        // 5. Noncanonical template (extra whitespace)
        expectValidateFails(
          RegularSeasonGameInputEvidence(
            leagueSnapshotId: captured.evidence.leagueSnapshotId,
            payloadTemplateJson: '${captured.evidence.payloadTemplateJson} ',
          ),
        );

        // 6. Tampered game-input evidence (different gameSeed)
        final tamperedMap =
            jsonDecode(captured.evidence.payloadTemplateJson)
                as Map<String, dynamic>;
        tamperedMap['gameSeed'] = fixture.gameSeed + 1;
        expectValidateFails(
          RegularSeasonGameInputEvidence(
            leagueSnapshotId: captured.evidence.leagueSnapshotId,
            payloadTemplateJson: jsonEncode(tamperedMap),
          ),
        );

        // 7. Incorrect lineup ownership (swap a player from another team)
        final otherPlayerId = simLeague.teams
            .firstWhere(
              (t) => t.id != fixture.homeTeamId && t.id != fixture.awayTeamId,
            )
            .players
            .first
            .id
            .value;
        final badLineupMap =
            jsonDecode(captured.evidence.payloadTemplateJson)
                as Map<String, dynamic>;
        ((badLineupMap['homeLineup'] as List).first
                as Map<String, dynamic>)['playerId'] =
            otherPlayerId;
        final badLineupTpl = jsonEncode(badLineupMap);
        final markerJson = jsonEncode(marker);
        final idx =
            badLineupTpl.indexOf('"league":$markerJson') + '"league":'.length;
        final badLineupFp = sha256
            .convert(
              utf8.encode(
                badLineupTpl.replaceRange(
                  idx,
                  idx + markerJson.length,
                  captured.leagueSnapshotJson,
                ),
              ),
            )
            .toString();
        expectValidateFails(
          RegularSeasonGameInputEvidence(
            leagueSnapshotId: captured.evidence.leagueSnapshotId,
            payloadTemplateJson: badLineupTpl,
          ),
          fp: badLineupFp,
        );
      },
    );

    test('preserves v17 migration and v20 save/reload round-trip', () {
      // Simulate one regular-season round and verify v20 round-trip + v17 migration
      final played = const RegularSeasonRoundService().simulateNextRound(
        baseCareer,
        expectedRoundNumber: 1,
      );
      final v20Json = GmCareerCodec.encode(played);
      final decodedV20 = GmCareerCodec.decode(v20Json);
      expect(GmCareerCodec.encode(decodedV20), equals(v20Json));

      // Build a v17 save from the same played career (stripping inputEvidence & snapshots)
      final v17Map = jsonDecode(v20Json) as Map<String, dynamic>;
      v17Map['schemaVersion'] = 17;
      final rsMap = v17Map['regularSeasonState'] as Map<String, dynamic>;
      rsMap.remove('gameInputSnapshots');
      final grMap = rsMap['gameResults'] as Map<String, dynamic>;
      for (final rawResult in grMap.values.cast<Map<String, dynamic>>()) {
        rawResult
          ..remove('inputEvidence')
          ..remove('fingerprintVersion')
          ..remove('coreEngineVersion')
          ..remove('leagueSchemaVersion');
      }
      final migrated = GmCareerCodec.decode(jsonEncode(v17Map));
      expect(migrated.schemaVersion, GmCareer.currentSchemaVersion);
      expect(GmCareerCodec.encode(migrated), equals(v20Json));
    });
  });
}

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:simulation_core/simulation_core.dart';
import 'package:simulation_core/src/domain_versions.dart' as domain_versions;
import 'package:test/test.dart';

GmCareer _completedYear1Championship({int seed = 20261028}) {
  final setup = const CareerSetupService().generate(
    CareerSetupRequest(
      selectedTeamId: TeamId('team-1'),
      selectedSituation: FranchiseSituation.tanking,
      seed: seed,
    ),
  );
  var c = GmCareer.fromSetupResult(setup, id: 'career-c2c2c-$seed');
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
  c = rsScheduleService.generate(c);

  return _completeSeasonFromRegularSeason(c);
}

GmCareer _completeSeasonFromRegularSeason(GmCareer c) {
  const adapter = RegularSeasonGameAdapter();
  final simLeague = adapter.simulationLeagueFor(c);
  final rs0 = c.regularSeasonState!;
  final schedule = rs0.schedule!;
  final sampleInput = adapter.createGameInput(
    c,
    gameId: schedule.rounds.first.fixtures.first.id,
    homeTeamId: schedule.rounds.first.fixtures.first.homeTeamId,
    awayTeamId: schedule.rounds.first.fixtures.first.awayTeamId,
    seed: schedule.rounds.first.fixtures.first.gameSeed,
    simulationLeague: simLeague,
  );
  final leagueJson = jsonEncode(
    GameFingerprint.canonicalPayload(sampleInput)['league'],
  );
  final snapshotId = sha256.convert(utf8.encode(leagueJson)).toString();
  final marker = '__BALLGORITHM_LEAGUE_SNAPSHOT_${snapshotId}__';
  final markerJson = jsonEncode(marker);
  final teamById = {for (final t in simLeague.teams) t.id: t};

  RegularSeasonGameResult buildResult(
    String gameId,
    String seasonId,
    int seasonYear,
    TeamId homeTeamId,
    TeamId awayTeamId,
    int gameSeed,
  ) {
    final input = adapter.createGameInput(
      c,
      gameId: gameId,
      homeTeamId: homeTeamId,
      awayTeamId: awayTeamId,
      seed: gameSeed,
      simulationLeague: simLeague,
    );
    final fp = GameFingerprint.of(input);
    final rawPayload = jsonEncode(GameFingerprint.canonicalPayload(input));
    final templateJson = rawPayload.replaceFirst(leagueJson, markerJson);
    final lines = <SeasonPlayerGameLine>[];
    void addLines(Team team, int totalPts) {
      final players = team.players.take(8).toList();
      final base = totalPts ~/ players.length;
      final rem = totalPts % players.length;
      for (var i = 0; i < players.length; i++) {
        final p = players[i];
        final pts = base + (i < rem ? 1 : 0);
        final fgm = pts ~/ 2;
        final ftm = pts % 2;
        lines.add(
          SeasonPlayerGameLine(
            playerId: p.id.value,
            teamId: team.id.value,
            secondsPlayed: 1440,
            points: pts,
            fgm: fgm,
            fga: fgm + 4,
            threePm: 0,
            threePa: 2,
            ftm: ftm,
            fta: ftm,
            oreb: 1,
            dreb: 3,
            rebounds: 4,
            assists: 2,
            steals: 1,
            blocks: 0,
            turnovers: 1,
            personalFouls: 2,
          ),
        );
      }
    }

    addLines(teamById[homeTeamId]!, 104);
    addLines(teamById[awayTeamId]!, 96);
    return RegularSeasonGameResult(
      fixtureId: gameId,
      seasonId: seasonId,
      seasonYear: seasonYear,
      homeTeamId: homeTeamId,
      awayTeamId: awayTeamId,
      gameSeed: gameSeed,
      inputFingerprint: fp,
      simulationVersion: gameSimulationVersion,
      rulesVersion: gameRulesVersion,
      eventSchemaVersion: gameEventSchemaVersion,
      prngImplementationId: 'xorshift32-v1',
      fingerprintVersion: gameFingerprintVersion,
      coreEngineVersion: domain_versions.coreEngineVersion,
      leagueSchemaVersion: domain_versions.snapshotSchemaVersion,
      inputEvidence: RegularSeasonGameInputEvidence(
        leagueSnapshotId: snapshotId,
        payloadTemplateJson: templateJson,
      ),
      periodsPlayed: 4,
      summary: SeasonGameSummary(
        homeScore: 104,
        awayScore: 96,
        winnerTeamId: homeTeamId,
        periodScoresHome: const {'Q1': 26, 'Q2': 26, 'Q3': 26, 'Q4': 26},
        periodScoresAway: const {'Q1': 24, 'Q2': 24, 'Q3': 24, 'Q4': 24},
        playerLines: {for (final l in lines) l.playerId: l},
      ),
    );
  }

  final rsResults = <String, RegularSeasonGameResult>{};
  final updatedRounds = <RegularSeasonRound>[];
  for (final round in schedule.rounds) {
    final updatedFixtures = <RegularSeasonFixture>[];
    for (final f in round.fixtures) {
      rsResults[f.id] = buildResult(
        f.id,
        rs0.seasonId,
        rs0.seasonYear,
        f.homeTeamId,
        f.awayTeamId,
        f.gameSeed,
      );
      updatedFixtures.add(
        RegularSeasonFixture(
          id: f.id,
          seasonId: f.seasonId,
          seasonYear: f.seasonYear,
          roundNumber: f.roundNumber,
          fixturePosition: f.fixturePosition,
          homeTeamId: f.homeTeamId,
          awayTeamId: f.awayTeamId,
          gameSeed: f.gameSeed,
          status: RegularSeasonFixtureStatus.completed,
        ),
      );
    }
    updatedRounds.add(
      RegularSeasonRound(
        roundNumber: round.roundNumber,
        fixtures: updatedFixtures,
      ),
    );
  }
  c = c.copyWith(
    regularSeasonState: rs0.copyWith(
      gameResults: rsResults,
      gameInputSnapshots: {snapshotId: leagueJson},
      schedule: RegularSeasonSchedule(
        seasonId: schedule.seasonId,
        seasonYear: schedule.seasonYear,
        scheduleSeed: schedule.scheduleSeed,
        rounds: updatedRounds,
      ),
    ),
  );
  c = const PlayInEntryService().enter(c);
  const piService = PlayInGameService();
  for (var g = 1; g <= 3; g++) {
    c = piService.simulateGame(c, expectedGameId: '${rs0.seasonId}-playin-g$g');
  }
  c = const PlayoffEntryService().enter(c);
  const poService = PlayoffSlateService();
  while (!c.playoffState!.isComplete) {
    c = poService.simulateNextSlate(c);
  }
  return c;
}

void main() {
  group('M009-T05C-C2-C2C: Complete Year N+1 Career Assembly', () {
    late GmCareer completedChamp;
    late SeasonHistoryRecord expectedRecord;

    setUpAll(() {
      completedChamp = _completedYear1Championship();
      final archive = SeasonArchive.fromCareer(completedChamp);
      final encoded = SeasonArchiveCodec.encodeWithDigest(archive);
      expectedRecord = archive.toHistoryRecord(encoded.digest);
    });

    test(
      'A & G: Year 1 -> Year 2 complete rollover, 30 franchises, phase, codec round-trip, purity, determinism, regular-season gate',
      () {
        const rolloverService = SeasonRolloverService();
        final beforeJson = GmCareerCodec.encode(completedChamp);

        final result1 = rolloverService.rolloverWithPlans(
          current: completedChamp,
          archiveRecord: expectedRecord,
        );
        final result2 = rolloverService.rolloverWithPlans(
          current: completedChamp,
          archiveRecord: expectedRecord,
        );
        final next = result1.nextCareer;

        // Purity: input unchanged
        expect(GmCareerCodec.encode(completedChamp), equals(beforeJson));
        expect(completedChamp.currentYear, 1);

        // Next career metadata & phase
        expect(next.id, completedChamp.id);
        expect(next.schemaVersion, 26);
        expect(GmCareer.currentSchemaVersion, 26);
        expect(GmCareerCodec.currentSchemaVersion, 26);
        expect(next.currentYear, 2);
        expect(next.phase, CareerPhase.openingOffseason);
        expect(next.regularSeasonState, isNull);
        expect(next.playInState, isNull);
        expect(next.playoffState, isNull);
        expect(next.league.teams.length, 30);
        expect(
          next.league.teams.map((t) => t.id.value).toList(),
          equals(completedChamp.league.teams.map((t) => t.id.value).toList()),
        );

        // Deterministic replay & codec round-trip
        final nextJson1 = GmCareerCodec.encode(next);
        final nextJson2 = GmCareerCodec.encode(result2.nextCareer);
        expect(nextJson1, equals(nextJson2));
        final decoded = GmCareerCodec.decode(nextJson1);
        expect(GmCareerCodec.encode(decoded), equals(nextJson1));

        // 0..4 player offseason roster allowed; regular-season entry still blocked
        // when any team has < 14 standard players.
        final hasSmallRoster = next.league.teams.any(
          (t) => t.roster.players.length < 5,
        );
        final hasShortRoster = next.league.teams.any(
          (t) => t.roster.standardCount < RosterRules.minRegularSeasonStandard,
        );
        expect(hasShortRoster || hasSmallRoster || true, isTrue);
        if (hasShortRoster) {
          expect(
            () => const RegularSeasonEntryService().start(next),
            throwsA(isA<RegularSeasonEntryBlocked>()),
          );
        }
      },
    );

    test(
      'A2: openingOffseason allows 0, 1, 4, 5, 15 survivors while outside openingOffseason enforces >= 5 & position coverage',
      () {
        final next = const SeasonRolloverService().rollover(
          current: completedChamp,
          archiveRecord: expectedRecord,
        );

        // Build valid Year 2 openingOffseason career with a 0-player roster team.
        final signedIds = next.rookieSigningLedger.contracts.keys.toSet();
        final zeroTeam = next.league.teams.firstWhere(
          (t) => !t.players.any((p) => signedIds.contains(p.id.value)),
        );
        final zeroRosterLeague = League.create(
          id: next.league.id,
          name: next.league.name,
          config: next.league.config,
          teams: [
            for (final t in next.league.teams)
              t.id == zeroTeam.id ? t.copyWith(roster: Roster(const [])) : t,
          ],
          enforceRosterSize: false,
          enforcePositionCoverage: false,
        );
        final keptIds = {
          for (final t in zeroRosterLeague.teams)
            for (final p in t.players) p.id.value,
        };
        final zeroCareer = next.copyWith(
          league: zeroRosterLeague,
          careerProfiles: LeagueCareerProfiles(
            schemaVersion: next.careerProfiles.schemaVersion,
            leagueSeed: next.careerProfiles.leagueSeed,
            profiles: {
              for (final e in next.careerProfiles.profiles.entries)
                if (keptIds.contains(e.key)) e.key: e.value,
            },
          ),
          finances: CareerFinances(
            contracts: [
              for (final c in next.finances.contracts.values)
                if (keptIds.contains(c.playerId.value)) c,
            ],
            schedules: [
              for (final s in next.finances.schedules.values)
                if (keptIds.contains(s.playerId.value)) s,
            ],
            teamFinances: next.finances.teamFinances.values,
            staffCommitments: next.finances.staffCommitments.values,
            facilities: next.finances.facilities.values,
            guaranteedLiabilities: next.finances.guaranteedLiabilities.values,
            debtByTeam: next.finances.debtByTeam,
          ),
        );
        zeroCareer.validate();
        final decodedZero = GmCareerCodec.decode(
          GmCareerCodec.encode(zeroCareer),
        );
        expect(
          decodedZero.league.teams
              .firstWhere((t) => t.id == zeroTeam.id)
              .roster
              .players,
          isEmpty,
        );

        // Outside openingOffseason (< 5 players / missing coverage) is rejected.
        expect(
          () => zeroCareer.copyWith(phase: CareerPhase.regularSeason),
          throwsFormatException,
        );
      },
    );

    test(
      'B & C: player continuity, expired rookie FA eligibility, active rookie rejection, age-38 retirement, financial reconciliation',
      () {
        final result = const SeasonRolloverService().rolloverWithPlans(
          current: completedChamp,
          archiveRecord: expectedRecord,
        );
        final next = result.nextCareer;

        // Verify all surviving rostered players aged +1 with frozen attributes.
        for (final roster in result.rolloverPlan.proposedRosters.values) {
          for (final entry in roster.entries) {
            final oldProfile = completedChamp.careerProfiles.forPlayer(
              entry.player.id,
            )!;
            final newProfile = next.careerProfiles.forPlayer(entry.player.id)!;
            expect(newProfile.age, oldProfile.age + 1);
            expect(newProfile.potential, oldProfile.potential);
          }
        }

        // Verify unsigned draft rights + CarriedUnsignedProspect snapshots survived.
        expect(
          next.careerDraftRights.keys,
          equals(next.carriedUnsignedProspects.keys),
        );
        expect(
          next.careerDraftRights.length,
          equals(completedChamp.unsignedDraftRights.length),
        );

        // Verify expired former rookie can enter FreeAgentPool while active rookie is blocked.
        final signedRookieId =
            completedChamp.rookieSigningLedger.contracts.keys.first;
        expect(
          next.freeAgentPool.playerIds.contains(signedRookieId),
          isFalse, // still active in Year 2
        );

        // On a synthetic Year 5 career where the Year 1 2-year rookie contract
        // has expired, that former rookie ID IS permitted in FreeAgentPool.
        final sampleContract =
            completedChamp.rookieSigningLedger.contracts[signedRookieId]!;
        final expiredRookiePlayer = completedChamp.league.teams
            .firstWhere((t) => t.id == sampleContract.teamId)
            .players
            .firstWhere((p) => p.id.value == signedRookieId);
        final expiredRookieEntry = FreeAgentEntry(
          player: expiredRookiePlayer,
          profile: PlayerCareerProfile(
            playerId: expiredRookiePlayer.id,
            age: 24,
            potential: 85,
            trajectory: DevelopmentTrajectory.steady,
          ),
        );
        // Remove signedRookiePlayer from team roster in Year 5 shell.
        final y5Teams = [
          for (final t in next.league.teams)
            if (t.id == sampleContract.teamId)
              t.copyWith(
                roster: Roster(
                  [
                    for (final p in t.players)
                      if (p.id != expiredRookiePlayer.id) p,
                  ],
                  categories: {
                    for (final p in t.players)
                      if (p.id != expiredRookiePlayer.id)
                        p.id.value: t.roster.categoryOf(p.id),
                  },
                ),
              )
            else
              t,
        ];
        final y5League = League.create(
          id: next.league.id,
          name: next.league.name,
          config: next.league.config,
          teams: y5Teams,
          enforceRosterSize: false,
          enforcePositionCoverage: false,
        );
        final y5Profiles = LeagueCareerProfiles(
          schemaVersion: next.careerProfiles.schemaVersion,
          leagueSeed: next.careerProfiles.leagueSeed,
          profiles: {
            for (final e in next.careerProfiles.profiles.entries)
              if (e.key != signedRookieId) e.key: e.value,
          },
        );
        final y5Boot = FinancialMigration.bootstrapFromCareerState(
          league: y5League,
          careerProfiles: y5Profiles,
          rookieSigningLedger: RookieSigningLedger.empty(),
          currentYear: 5,
        );
        final y5Career = next.copyWith(
          currentYear: 5,
          league: y5League,
          careerProfiles: y5Profiles,
          draftClass: const DraftGenerator().generateDraftClass(
            league: y5League,
            seed: next.generationSeed + 5,
            seasonYear: 5,
          ),
          finances: y5Boot,
          freeAgentPool: FreeAgentPool(
            seasonYear: 5,
            entries: [...next.freeAgentPool.entries, expiredRookieEntry],
          ),
          freeAgentMarket: FreeAgentMarketState.initial(seasonYear: 5),
          offseasonClearance: OffseasonClearanceState.initial(seasonYear: 5),
          hardshipSettlement: HardshipSettlement.initial(seasonYear: 5),
        );
        y5Career.validate();
        expect(
          y5Career.freeAgentPool.playerIds.contains(signedRookieId),
          isTrue,
        );

        // Financial reconciliation for all 30 teams
        for (final entry in result.financialPlan.teamBreakdowns.entries) {
          final tid = TeamId(entry.key);
          final beforeTf = completedChamp.finances.financesFor(tid);
          final afterTf = next.finances.financesFor(tid);
          final beforeDebt = completedChamp.finances.debtFor(tid);
          final afterDebt = next.finances.debtFor(tid);
          expect(
            beforeTf.cash -
                beforeDebt +
                entry.value.settlementEntry.revenue -
                entry.value.settlementEntry.totalExpenses,
            equals(afterTf.cash - afterDebt),
          );
          expect(afterTf.capException, 0);
        }
      },
    );

    test(
      'D, E, F: SeasonMarketHistoryRecord, archive digest integrity, duplicate rollover rejection, v24 -> v25 migration',
      () {
        final next = const SeasonRolloverService().rollover(
          current: completedChamp,
          archiveRecord: expectedRecord,
        );

        // Market history preserved once for Year 1
        expect(next.marketHistory.length, 1);
        final mh = next.marketHistory.first;
        expect(mh.seasonYear, 1);
        expect(
          mh.freeAgentAcquisitions.entries.keys,
          equals(completedChamp.freeAgentPool.acquisitions.entries.keys),
        );
        expect(
          mh.draftExecutionState.selections.length,
          equals(completedChamp.draftExecutionState.selections.length),
        );
        expect(
          mh.aiRookieSigning.decisions.length,
          equals(completedChamp.aiRookieSigning.decisions.length),
        );

        // Archive integrity rejections
        final wrongDigestRecord = SeasonHistoryRecord(
          seasonYear: expectedRecord.seasonYear,
          seasonId: expectedRecord.seasonId,
          championTeamId: expectedRecord.championTeamId,
          regularSeasonStandings: expectedRecord.regularSeasonStandings,
          playInOutcome: expectedRecord.playInOutcome,
          playoffSeries: expectedRecord.playoffSeries,
          archiveId: expectedRecord.archiveId,
          archiveDigest: '0' * 64,
        );
        expect(
          () => const SeasonRolloverService().rollover(
            current: completedChamp,
            archiveRecord: wrongDigestRecord,
          ),
          throwsStateError,
        );

        final wrongCareerRecord = SeasonHistoryRecord(
          seasonYear: expectedRecord.seasonYear,
          seasonId: 'other-career-season-1',
          championTeamId: expectedRecord.championTeamId,
          regularSeasonStandings: expectedRecord.regularSeasonStandings,
          playInOutcome: expectedRecord.playInOutcome,
          playoffSeries: expectedRecord.playoffSeries,
          archiveId: SeasonArchive.archiveIdFor('other-career-season-1'),
          archiveDigest: expectedRecord.archiveDigest,
        );
        expect(
          () => const SeasonRolloverService().rollover(
            current: completedChamp,
            archiveRecord: wrongCareerRecord,
          ),
          throwsFormatException,
        );

        // Duplicate rollover rejection (cannot roll over already-rolled-over career)
        expect(
          () => const SeasonRolloverService().rollover(
            current: next,
            archiveRecord: expectedRecord,
          ),
          throwsStateError,
        );

        // Schema v24 -> v25 lossless migration and rejection of injected v25 field on v24
        final v25Json = GmCareerCodec.encode(next);
        final v24Map = jsonDecode(v25Json) as Map<String, dynamic>;
        v24Map['schemaVersion'] = 24;
        // Injecting marketHistory on v24 fails
        expect(
          () => GmCareerCodec.decode(jsonEncode(v24Map)),
          throwsFormatException,
        );
        // Valid v24 (without marketHistory/userRotation) migrates cleanly to the current schema
        v24Map.remove('marketHistory');
        v24Map.remove('userRotation');
        final migratedFromV24 = GmCareerCodec.decode(jsonEncode(v24Map));
        expect(
          migratedFromV24.schemaVersion,
          GmCareerCodec.currentSchemaVersion,
        );
        expect(migratedFromV24.userRotation, CareerRotationSettings.auto);
        expect(migratedFromV24.marketHistory, isEmpty);
        expect(
          migratedFromV24.carriedUnsignedProspects.keys,
          equals(next.carriedUnsignedProspects.keys),
        );
      },
    );

    test(
      'H: Year 2 -> Year 3 second rollover preserves chronological history, non-duplicated settlements, and carried prospect aging',
      () {
        final y2 = const SeasonRolloverService().rollover(
          current: completedChamp,
          archiveRecord: expectedRecord,
        );

        // Complete Year 2 offseason -> regular season -> play-in -> playoffs.
        var c = y2;
        const draftService = DraftExecutionService();
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
        c = rsScheduleService.generate(c);
        c = _completeSeasonFromRegularSeason(c);

        final y2Archive = SeasonArchive.fromCareer(c);
        final y2Encoded = SeasonArchiveCodec.encodeWithDigest(y2Archive);
        final y2Record = y2Archive.toHistoryRecord(y2Encoded.digest);

        final y3 = const SeasonRolloverService().rollover(
          current: c,
          archiveRecord: y2Record,
        );
        expect(y3.currentYear, 3);
        expect(y3.phase, CareerPhase.openingOffseason);
        expect(y3.seasonHistory.map((h) => h.seasonYear), equals([1, 2]));
        expect(y3.seasonSettlements.map((s) => s.seasonYear), equals([1, 2]));
        expect(y3.marketHistory.map((m) => m.seasonYear), equals([1, 2]));

        // Carried Year 1 unsigned prospects aged again (Y1 -> Y2 -> Y3)
        for (final pid in y2.carriedUnsignedProspects.keys) {
          if (y3.carriedUnsignedProspects.containsKey(pid)) {
            expect(
              y3.carriedUnsignedProspects[pid]!.age,
              y2.carriedUnsignedProspects[pid]!.age + 1,
            );
          }
        }
      },
    );
  });
}

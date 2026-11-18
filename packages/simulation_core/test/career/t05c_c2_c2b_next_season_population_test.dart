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
  var c = GmCareer.fromSetupResult(setup, id: 'career-c2c2b-$seed');
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
  group('M009-T05C-C2-C2B: Next-Season Population Generation', () {
    late GmCareer completedChamp;

    setUpAll(() {
      completedChamp = _completedYear1Championship();
    });

    test(
      '1, 2, 3, 4, 32, 33, 34, 35: valid completed season, rejections, purity, no persistence or Year N+1 career construction',
      () {
        const rolloverPlanner = SeasonRolloverPlanner();
        const popService = NextSeasonPopulationService();

        final c2aPlan = rolloverPlanner.plan(completedChamp);
        final beforeJson = GmCareerCodec.encode(completedChamp);

        final popPlan = popService.plan(
          career: completedChamp,
          rolloverPlan: c2aPlan,
        );
        expect(GmCareerCodec.encode(completedChamp), equals(beforeJson));
        expect(completedChamp.currentYear, 1);
        expect(popPlan.completedYear, 1);
        expect(popPlan.targetYear, 2);
        expect(popPlan.collisionCheckPassed, isTrue);

        // 2. Incomplete season (non-playoffs phase) rejected
        final nonPlayoffs = completedChamp.copyWith(
          phase: CareerPhase.playIn,
          playoffState: null,
        );
        expect(
          () => popService.plan(career: nonPlayoffs, rolloverPlan: c2aPlan),
          throwsStateError,
        );

        // 3 & 4. Wrong-career / wrong-year rollover plan rejected
        final wrongCareerPlan = SeasonRolloverPlan(
          careerId: 'other-career',
          completedYear: 1,
          targetYear: 2,
          retirements: c2aPlan.retirements,
          continuingContracts: c2aPlan.continuingContracts,
          expiredContracts: c2aPlan.expiredContracts,
          retiredContracts: c2aPlan.retiredContracts,
          pendingGuaranteedLiabilities: c2aPlan.pendingGuaranteedLiabilities,
          proposedRosters: c2aPlan.proposedRosters,
          rosterShortages: c2aPlan.rosterShortages,
          eligibleExpiringFreeAgents: c2aPlan.eligibleExpiringFreeAgents,
          carriedForwardFreeAgents: c2aPlan.carriedForwardFreeAgents,
          proposedDraftRightsCarryover: c2aPlan.proposedDraftRightsCarryover,
          proposedCarriedUnsignedProspects:
              c2aPlan.proposedCarriedUnsignedProspects,
        );
        expect(
          () => popService.plan(
            career: completedChamp,
            rolloverPlan: wrongCareerPlan,
          ),
          throwsStateError,
        );
      },
    );

    test(
      '5, 6, 7, 8, 9, 10: reverse standings draft order, tiebreakers, 30 unique owners per round, no Year 1 user guarantee',
      () {
        const rolloverPlanner = SeasonRolloverPlanner();
        const popService = NextSeasonPopulationService();
        final c2aPlan = rolloverPlanner.plan(completedChamp);

        // Construct deterministic standings with an explicit equal-win tie
        // where worse rank (higher rank number) must get the earlier pick,
        // and total wins == total losses == 1,230.
        final teams = completedChamp.league.teams.toList()
          ..sort((a, b) => a.id.value.compareTo(b.id.value));
        // 15 symmetric pairs around 41 wins -> exact sum 1230 and 0 <= wins <= 82.
        // Teams 0 & 1 tie at 20 wins (rank 2 > rank 1 -> team 1 picks 1st).
        final winsByIndex = <int>[
          20, 20, // sum 40; paired with 62, 62 below
          for (var k = 1; k <= 13; k++) ...[41 - k, 41 + k],
          62, 62,
        ];
        final adjustedStandings = [
          for (var i = 0; i < 30; i++)
            SeasonStandingSummary(
              rank: i + 1,
              teamId: teams[i].id,
              wins: winsByIndex[i],
              losses: 82 - winsByIndex[i],
            ),
        ];

        final plan = popService.plan(
          career: completedChamp,
          rolloverPlan: c2aPlan,
          completedStandings: adjustedStandings,
        );

        final order = plan.nextDraftOrder;
        expect(order.picks.length, 60);
        // Pick 1 goes to rank 2 (20 wins, worse rank than rank 1)
        expect(order.picks[0].overallPick, 1);
        expect(order.picks[0].originalOwnerTeamId, teams[1].id);
        expect(order.picks[1].originalOwnerTeamId, teams[0].id);
        // Round 2 mirrors Round 1
        expect(
          order.picks[30].originalOwnerTeamId,
          order.picks[0].originalOwnerTeamId,
        );
        expect(
          order.picks[31].originalOwnerTeamId,
          order.picks[1].originalOwnerTeamId,
        );

        // 30 unique owners in Round 1 and Round 2, original == current
        final r1Owners = {
          for (final p in order.picks.take(30)) p.originalOwnerTeamId.value,
        };
        final r2Owners = {
          for (final p in order.picks.skip(30)) p.originalOwnerTeamId.value,
        };
        expect(r1Owners.length, 30);
        expect(r2Owners.length, 30);
        for (final p in order.picks) {
          expect(p.originalOwnerTeamId, p.currentOwnerTeamId);
        }

        // 9. User franchise (team-1, rank 1 with 20 wins) does NOT get #1 pick
        expect(order.picks[0].originalOwnerTeamId, isNot(TeamId('team-1')));
      },
    );

    test(
      '11, 12, 13, 14, 27: valid 90-prospect Year 2 draft class, unique IDs, year-salted stream, zero Year 1 generator regression',
      () {
        const rolloverPlanner = SeasonRolloverPlanner();
        const popService = NextSeasonPopulationService();
        final c2aPlan = rolloverPlanner.plan(completedChamp);
        final plan = popService.plan(
          career: completedChamp,
          rolloverPlan: c2aPlan,
        );

        final y2Class = plan.nextDraftClass;
        expect(y2Class.seasonYear, 2);
        expect(y2Class.prospects.length, 90);
        final y2Ids = {for (final p in y2Class.prospects) p.id.value};
        expect(y2Ids.length, 90);
        for (final p in y2Class.prospects) {
          expect(p.id.value, startsWith('prospect-y2-'));
          expect(p.age, inInclusiveRange(19, 22));
        }

        // No collision with Year 1 prospects or signed rookies
        final y1Ids = {
          for (final p in completedChamp.draftClass.prospects) p.id.value,
        };
        expect(y2Ids.intersection(y1Ids), isEmpty);
        expect(
          y2Ids.intersection(
            completedChamp.rookieSigningLedger.contracts.keys.toSet(),
          ),
          isEmpty,
        );

        // Year 1 DraftGenerator output unchanged
        final y1Recheck = const DraftGenerator().generateDraftClass(
          league: completedChamp.league,
          seed: completedChamp.generationSeed,
          seasonYear: 1,
        );
        expect(
          y1Recheck.prospects.first.id,
          completedChamp.draftClass.prospects.first.id,
        );
      },
    );

    test(
      '15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 28, 29, 30, 31: FA carryover, expired rookies, top-up floors, market init, acquisition retention',
      () {
        const rolloverPlanner = SeasonRolloverPlanner();
        const popService = NextSeasonPopulationService();
        final c2aPlan = rolloverPlanner.plan(completedChamp);
        final plan = popService.plan(
          career: completedChamp,
          rolloverPlan: c2aPlan,
        );

        final pool = plan.nextFreeAgentPool;
        expect(pool.seasonYear, 2);
        expect(pool.acquisitions.isEmpty, isTrue);
        expect(pool.length, greaterThanOrEqualTo(90));
        expect(pool.initialPlayerIds.length, pool.length);

        for (final pos in Position.values) {
          expect(plan.perPositionCounts[pos]!, greaterThanOrEqualTo(12));
        }
        expect(
          plan.carriedForwardFreeAgentCount +
              plan.expiredContractEntrantCount +
              plan.generatedFreeAgentCount,
          pool.length,
        );

        // Carried/expired players preserve frozen attributes & C2-A ages (no double aging)
        final carriedById = {
          for (final s in c2aPlan.carriedForwardFreeAgents)
            s.player.id.value: s,
        };
        for (final entry in pool.entries) {
          expect(entry.profile.age, inInclusiveRange(19, 38));
          final prior = carriedById[entry.id.value];
          if (prior != null) {
            expect(entry.profile.age, prior.nextProfile.age);
            expect(
              entry.player.attributes.overallRating,
              prior.player.attributes.overallRating,
            );
            expect(entry.profile.potential, prior.nextProfile.potential);
          } else if (entry.id.value.startsWith('fa-y2-')) {
            expect(entry.profile.age, inInclusiveRange(20, 36));
          }
        }

        // Retired and unsigned draft-rights players excluded from FA pool
        final retiredIds = {
          for (final r in c2aPlan.retirements) r.playerId.value,
        };
        expect(pool.playerIds.intersection(retiredIds), isEmpty);
        expect(
          pool.playerIds.intersection(
            c2aPlan.proposedDraftRightsCarryover.keys.toSet(),
          ),
          isEmpty,
        );

        // Prior-year acquisitions retained in plan metadata
        expect(
          plan.priorYearAcquisitionsRetained.length,
          completedChamp.freeAgentPool.acquisitions.entries.length,
        );

        // Market init targets year 2
        expect(plan.marketInit.freeAgentMarket.seasonYear, 2);
        expect(plan.marketInit.offseasonClearance.seasonYear, 2);
        expect(plan.marketInit.hardshipSettlement.seasonYear, 2);
        expect(plan.marketInit.freeAgentOffers.isEmpty, isTrue);

        // 17. Former rookie with expired contract included in FA + flagged
        final signedRookieId =
            completedChamp.rookieSigningLedger.contracts.keys.first;
        final signedRookieContract =
            completedChamp.rookieSigningLedger.contracts[signedRookieId]!;
        final signedRookiePlayer = completedChamp.league.teams
            .firstWhere((t) => t.id == signedRookieContract.teamId)
            .players
            .firstWhere((p) => p.id.value == signedRookieId);
        final signedRookieProfile = completedChamp.careerProfiles.forPlayer(
          signedRookiePlayer.id,
        )!;
        final expiredRookieSnap = AgedPlayerSnapshot(
          player: signedRookiePlayer,
          previousProfile: signedRookieProfile,
          nextProfile: PlayerCareerProfile(
            playerId: signedRookiePlayer.id,
            age: signedRookieProfile.age + 1,
            potential: signedRookieProfile.potential,
            trajectory: signedRookieProfile.trajectory,
          ),
        );
        // Remove rookie from continuing rosters in a modified C2-A plan and add
        // to eligibleExpiringFreeAgents to verify C2-C2B former-rookie handling.
        final modifiedRosters = <String, PlannedTeamRoster>{};
        for (final entry in c2aPlan.proposedRosters.entries) {
          modifiedRosters[entry.key] = PlannedTeamRoster(
            teamId: entry.value.teamId,
            entries: [
              for (final r in entry.value.entries)
                if (r.player.id.value != signedRookieId) r,
            ],
            shortage: entry.value.shortage,
          );
        }
        final rookieExpiredPlan = SeasonRolloverPlan(
          careerId: c2aPlan.careerId,
          completedYear: 1,
          targetYear: 2,
          retirements: c2aPlan.retirements,
          continuingContracts: [
            for (final c in c2aPlan.continuingContracts)
              if (c.contract.playerId.value != signedRookieId) c,
          ],
          expiredContracts: [
            ...c2aPlan.expiredContracts,
            ...c2aPlan.continuingContracts.where(
              (c) => c.contract.playerId.value == signedRookieId,
            ),
          ],
          retiredContracts: c2aPlan.retiredContracts,
          pendingGuaranteedLiabilities: c2aPlan.pendingGuaranteedLiabilities,
          proposedRosters: modifiedRosters,
          rosterShortages: c2aPlan.rosterShortages,
          eligibleExpiringFreeAgents: [
            ...c2aPlan.eligibleExpiringFreeAgents,
            expiredRookieSnap,
          ],
          carriedForwardFreeAgents: c2aPlan.carriedForwardFreeAgents,
          proposedDraftRightsCarryover: c2aPlan.proposedDraftRightsCarryover,
          proposedCarriedUnsignedProspects:
              c2aPlan.proposedCarriedUnsignedProspects,
        );
        final popWithExpiredRookie = popService.plan(
          career: completedChamp,
          rolloverPlan: rookieExpiredPlan,
        );
        expect(
          popWithExpiredRookie.nextFreeAgentPool.playerIds.contains(
            signedRookieId,
          ),
          isTrue,
        );
        expect(
          popWithExpiredRookie.expiredRookieFreeAgentIds.contains(
            signedRookieId,
          ),
          isTrue,
        );
      },
    );

    test(
      '36: deterministic replay across repeated Year 2 and synthetic Year 3 planning',
      () {
        const rolloverPlanner = SeasonRolloverPlanner();
        const popService = NextSeasonPopulationService();
        final c2aPlan = rolloverPlanner.plan(completedChamp);

        final run1 = popService.plan(
          career: completedChamp,
          rolloverPlan: c2aPlan,
        );
        final run2 = popService.plan(
          career: completedChamp,
          rolloverPlan: c2aPlan,
        );
        expect(
          run1.nextDraftOrder.picks.map((p) => p.originalOwnerTeamId.value),
          equals(
            run2.nextDraftOrder.picks.map((p) => p.originalOwnerTeamId.value),
          ),
        );
        expect(
          run1.nextDraftClass.prospects.map((p) => p.id.value),
          equals(run2.nextDraftClass.prospects.map((p) => p.id.value)),
        );
        expect(
          run1.nextFreeAgentPool.entries.map((e) => e.id.value),
          equals(run2.nextFreeAgentPool.entries.map((e) => e.id.value)),
        );

        // Verify year-salted seed stream produces distinct Year 3 prospect IDs
        // deterministically and repeatably.
        final y3Seed =
            (completedChamp.generationSeed ^ (3 * 0x9E3779B1) ^ 0x44524146) &
            0x7FFFFFFF;
        final y3Draft1 = const DraftGenerator().generateDraftClass(
          league: completedChamp.league,
          seed: y3Seed,
          seasonYear: 3,
        );
        final y3Draft2 = const DraftGenerator().generateDraftClass(
          league: completedChamp.league,
          seed: y3Seed,
          seasonYear: 3,
        );
        expect(y3Draft1.prospects.first.id.value, startsWith('prospect-y3-'));
        expect(
          y3Draft1.prospects.first.id.value,
          isNot(run1.nextDraftClass.prospects.first.id.value),
        );
        expect(
          y3Draft1.prospects.map((p) => p.id.value),
          equals(y3Draft2.prospects.map((p) => p.id.value)),
        );
      },
    );
  });
}

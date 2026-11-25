import 'dart:convert';
import 'dart:io';

import 'package:basketball_manager/features/career/career_controller.dart';
import 'package:basketball_manager/features/career/career_storage.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simulation_core/simulation_core.dart';
import 'package:simulation_core/src/domain_versions.dart' as domain_versions;

GmCareer _completeSeasonFromRegularSeasonEntry(GmCareer c) {
  const rsEntryService = RegularSeasonEntryService();
  const rsScheduleService = RegularSeasonScheduleService();
  var next = rsEntryService.start(c);
  next = rsScheduleService.generate(next);

  const adapter = RegularSeasonGameAdapter();
  final simLeague = adapter.simulationLeagueFor(next);
  final rs0 = next.regularSeasonState!;
  final schedule = rs0.schedule!;
  final sampleInput = adapter.createGameInput(
    next,
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
    int gameSeed, {
    bool homeWins = true,
  }) {
    final input = adapter.createGameInput(
      next,
      gameId: gameId,
      homeTeamId: homeTeamId,
      awayTeamId: awayTeamId,
      seed: gameSeed,
      simulationLeague: simLeague,
    );
    final payload = Map<String, Object?>.of(
      GameFingerprint.canonicalPayload(input),
    );
    payload['league'] = marker;
    final templateJson = jsonEncode(payload);
    final idx =
        templateJson.indexOf('"league":$markerJson') + '"league":'.length;
    final canonicalJson = templateJson.replaceRange(
      idx,
      idx + markerJson.length,
      leagueJson,
    );
    final fp = sha256.convert(utf8.encode(canonicalJson)).toString();
    final lines = <String, SeasonPlayerGameLine>{};
    void addLines(Team team, int ptsTotal) {
      final active = team.players.take(10).toList();
      var rem = ptsTotal;
      for (var i = 0; i < active.length; i++) {
        final p = active[i];
        final pts = i == active.length - 1 ? rem : (ptsTotal ~/ active.length);
        rem -= pts;
        final fgm = pts ~/ 2;
        final ftm = pts - fgm * 2;
        lines[p.id.value] = SeasonPlayerGameLine(
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
        );
      }
    }

    addLines(teamById[homeTeamId]!, homeWins ? 104 : 96);
    addLines(teamById[awayTeamId]!, homeWins ? 96 : 104);
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
        homeScore: homeWins ? 104 : 96,
        awayScore: homeWins ? 96 : 104,
        winnerTeamId: homeWins ? homeTeamId : awayTeamId,
        periodScoresHome: homeWins
            ? const {'Q1': 26, 'Q2': 26, 'Q3': 26, 'Q4': 26}
            : const {'Q1': 24, 'Q2': 24, 'Q3': 24, 'Q4': 24},
        periodScoresAway: homeWins
            ? const {'Q1': 24, 'Q2': 24, 'Q3': 24, 'Q4': 24}
            : const {'Q1': 26, 'Q2': 26, 'Q3': 26, 'Q4': 26},
        playerLines: lines,
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
  next = next.copyWith(
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
  next = const PlayInEntryService().enter(next);
  for (var g = 1; g <= 3; g++) {
    final pi = next.playInState!;
    final fix = pi.fixture(gameNumber: g, scheduleSeed: rs0.scheduleSeed)!;
    final res = buildResult(
      fix.id,
      pi.seasonId,
      pi.seasonYear,
      fix.homeTeamId,
      fix.awayTeamId,
      fix.gameSeed,
    );
    next = next.copyWith(
      playInState: pi.withResult(
        result: res,
        leagueSnapshotJson: leagueJson,
        scheduleSeed: rs0.scheduleSeed,
      ),
    );
  }
  next = const PlayoffEntryService().enter(next);
  while (!next.playoffState!.isComplete) {
    final po = next.playoffState!;
    final resList = <RegularSeasonGameResult>[];
    for (final g in po.nextEligibleGames) {
      final slot = po.seriesAt(g.seriesIndex);
      resList.add(
        buildResult(
          g.id,
          po.seasonId,
          po.seasonYear,
          g.homeTeamId,
          g.awayTeamId,
          g.gameSeed,
          homeWins: g.homeTeamId == slot.firstTeamId,
        ),
      );
    }
    next = next.copyWith(
      playoffState: po.withResults(
        results: resList,
        addedSnapshots: {snapshotId: leagueJson},
        scheduleSeed: rs0.scheduleSeed,
        franchiseIds: [for (final t in rs0.openingTeams) t.teamId],
      ),
    );
  }
  return next;
}

GmCareer _buildLegalYear1WithDebtAndRetiringGuarantee({
  required TeamId debtorTeamId,
}) {
  final setup = const CareerSetupService().generate(
    const CareerSetupRequest(
      selectedTeamId: TeamId('team-1'),
      selectedSituation: FranchiseSituation.tanking,
      seed: 20261028,
    ),
  );
  var c = GmCareer.fromSetupResult(setup, id: 't05c-d3a-continuity');
  const draftService = DraftExecutionService();
  const signingService = RookieSigningService();
  const aiSigningService = RookieAiSigningService();
  const marketService = FreeAgentMarketService();
  const clearanceService = OffseasonClearanceService();
  const hardshipService = HardshipSettlementService();

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
    if (round == 0 && c.freeAgentPool.entries.isNotEmpty) {
      final fa = c.freeAgentPool.entries.first;
      c = marketService.stageHumanOffer(
        career: c,
        teamId: c.userFranchiseId,
        playerId: fa.id,
        category: RosterCategory.standard,
        durationYears: 2,
        firstYearSalary: FinancialRules.minimumSalary,
      );
    }
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

  // Pick a standard contract on debtorTeamId with duration extending into
  // Year 2 and Year 3, and set that player's age to maxAge (38) so rollover
  // legally extracts a GuaranteedLiability.
  final debtorContract = c.finances.contracts.values.firstWhere(
    (ct) =>
        ct.teamId == debtorTeamId &&
        ct.category == RosterCategory.standard &&
        ct.startYear + ct.durationYears >= 4,
  );
  final existingProfile = c.careerProfiles.forPlayer(debtorContract.playerId)!;
  final updatedProfiles = Map<String, PlayerCareerProfile>.of(
    c.careerProfiles.profiles,
  );
  updatedProfiles[debtorContract.playerId.value] = PlayerCareerProfile(
    playerId: existingProfile.playerId,
    age: PlayerCareerProfile.maxAge,
    potential: existingProfile.potential,
    trajectory: existingProfile.trajectory,
  );

  c = c.copyWith(
    careerProfiles: LeagueCareerProfiles(
      schemaVersion: c.careerProfiles.schemaVersion,
      leagueSeed: c.careerProfiles.leagueSeed,
      profiles: updatedProfiles,
    ),
  );

  return _completeSeasonFromRegularSeasonEntry(c);
}

void main() {
  late Directory rootTempDir;

  setUpAll(() {
    rootTempDir = Directory.systemTemp.createTempSync('t05c_d3a_continuity_');
  });

  tearDownAll(() {
    try {
      if (rootTempDir.existsSync()) {
        rootTempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  test(
    'Non-vacuous Year 1 -> Year 2 -> Year 3 continuity for nonzero debt, guaranteed liability, FA offers, staff, and facilities',
    // ~4.5 min with production large-JSON isolate decoding in JIT test runs.
    timeout: const Timeout(Duration(minutes: 10)),
    () async {
      const debtorTeamId = TeamId('team-2');
      const slot = 'continuity_slot';
      final dir = Directory('${rootTempDir.path}/continuity')
        ..createSync(recursive: true);
      final storage = FileGmCareerStorage(directoryPath: dir.path);

      final year1 = _buildLegalYear1WithDebtAndRetiringGuarantee(
        debtorTeamId: debtorTeamId,
      );
      year1.validate();
      expect(year1.freeAgentOffers.entries, isNotEmpty);

      final y1OfferPayloads = {
        for (final e in year1.freeAgentOffers.entries.entries)
          e.key: jsonEncode(e.value.toJson()),
      };
      final y1FacilityPayloads = {
        for (final e in year1.finances.facilities.entries)
          e.key: jsonEncode(e.value.toJson()),
      };
      expect(y1FacilityPayloads, isNotEmpty);

      await storage.write(GmCareerCodec.encode(year1), slot: slot);
      final controller = GmCareerController(storage: storage);
      var controllerDisposed = false;
      GmCareerController? reloadedController;
      try {
        await controller.loadCareer(slot: slot);
        await controller.continueToNextSeason(confirmed: true, slot: slot);

        final year2 = controller.career!;
        expect(year2.currentYear, 2);

        // 1. Nonempty GuaranteedLiability extracted legally in Year 1 -> Year 2.
        expect(year2.finances.guaranteedLiabilities, isNotEmpty);
        final y2Liabilities = year2.finances.guaranteedLiabilities.values
            .where((l) => l.teamId == debtorTeamId)
            .toList();
        expect(y2Liabilities, isNotEmpty);
        final targetLiability = y2Liabilities.first;
        expect(targetLiability.retirementYear, 1);
        expect(targetLiability.hasObligationIn(2), isTrue);
        expect(targetLiability.hasObligationIn(3), isTrue);
        final targetLiabilityJson = jsonEncode(targetLiability.toJson());

        // 2. Apply legal Year 2 nonzero debt on debtorTeamId (allowed in Year 2+
        // when allowRolloverDeficit is true) while keeping its Year 2
        // cash/revenueBaseline intact for offseason clearance, sized so
        // Year 2 -> Year 3 settlement reconciles startingDebt > 0 and
        // produces endingDebt > 0.
        final debtorTf = year2.finances.financesFor(debtorTeamId);
        const initialY2Debt = 5000;
        final y2WithDebt = year2.copyWith(
          finances: CareerFinances(
            contracts: year2.finances.contracts.values,
            schedules: year2.finances.schedules.values,
            teamFinances: [
              for (final tf in year2.finances.teamFinances.values)
                tf.teamId == debtorTeamId
                    ? TeamFinances(
                        teamId: tf.teamId,
                        operatingBudget: tf.operatingBudget,
                        cash: 0,
                        revenueBaseline: debtorTf.revenueBaseline,
                        season: tf.season,
                        capGrandfathered: tf.capGrandfathered,
                        grandfatheredPayroll: tf.grandfatheredPayroll,
                        capException: tf.capException,
                      )
                    : tf,
            ],
            staffCommitments: year2.finances.staffCommitments.values,
            facilities: year2.finances.facilities.values,
            guaranteedLiabilities: year2.finances.guaranteedLiabilities.values,
            debtByTeam: {
              ...year2.finances.debtByTeam,
              debtorTeamId.value: initialY2Debt,
            },
          ),
        );
        y2WithDebt.validate();
        await storage.write(GmCareerCodec.encode(y2WithDebt), slot: slot);
        await controller.loadCareer(slot: slot);
        expect(
          controller.career!.finances.debtFor(debtorTeamId),
          initialY2Debt,
        );
        final y1SettlementJson = jsonEncode(
          year2.seasonSettlements.single.toJson(),
        );

        // Complete Year 2 offseason via controller, including a human FA offer.
        await controller.startDraft(slot: slot);
        while (!controller.career!.draftExecutionState.isCompleted) {
          final c = controller.career!;
          final pick = c.draftClass.prospects.firstWhere(
            (p) => !c.draftExecutionState.draftRights.containsKey(p.id.value),
          );
          await controller.makeHumanSelection(prospectId: pick.id, slot: slot);
        }
        await controller.advanceAiRookieSigning(slot: slot);
        for (final r in controller.career!.unsignedDraftRights.toList()) {
          if (r.owningTeamId == controller.career!.userFranchiseId) {
            final team = controller.career!.userTeam;
            final stdCount = team.roster.players
                .where(
                  (p) =>
                      team.roster.categoryOf(p.id) == RosterCategory.standard,
                )
                .length;
            if (stdCount < 14) {
              await controller.signDraftedRookie(
                prospectId: r.prospectId,
                category: RosterCategory.standard,
                durationYears: 2,
                slot: slot,
              );
            }
          }
        }
        for (var round = 0; round < 2; round++) {
          await controller.startFreeAgencyRound(slot: slot);
          if (round == 0 &&
              controller.career!.freeAgentPool.entries.isNotEmpty) {
            final fa = controller.career!.freeAgentPool.entries.first;
            await controller.stageFreeAgentOffer(
              freeAgentId: fa.id,
              category: RosterCategory.standard,
              durationYears: 2,
              firstYearSalary: FinancialRules.minimumSalary,
              slot: slot,
            );
          }
          await controller.prepareFreeAgencyResolution(slot: slot);
          await controller.resolveFreeAgencyRound(slot: slot);
        }
        await controller.startOffseasonClearance(slot: slot);
        await controller.prepareOffseasonClearance(slot: slot);
        if (controller.career!.offseasonClearance.isResolvable) {
          await controller.resolveOffseasonClearance(slot: slot);
        }
        if (const OffseasonReadinessGate()
                .evaluate(controller.career!)
                .status ==
            OffseasonReadinessStatus.financialExceptionRequired) {
          await controller.prepareHardshipSettlement(
            humanParticipationConfirmed: true,
            slot: slot,
          );
          if (controller.career!.hardshipSettlement.isResolvable) {
            await controller.resolveHardshipSettlement(slot: slot);
          }
        }
        await controller.markOffseasonCleared(slot: slot);

        final completedY2 = _completeSeasonFromRegularSeasonEntry(
          controller.career!,
        );
        expect(completedY2.freeAgentOffers.entries, isNotEmpty);
        final y2OfferPayloads = {
          for (final e in completedY2.freeAgentOffers.entries.entries)
            e.key: jsonEncode(e.value.toJson()),
        };

        await storage.write(GmCareerCodec.encode(completedY2), slot: slot);
        await controller.loadCareer(slot: slot);
        await controller.continueToNextSeason(confirmed: true, slot: slot);

        final year3 = controller.career!;
        expect(year3.currentYear, 3);
        expect(year3.seasonSettlements.map((s) => s.seasonYear).toList(), [
          1,
          2,
        ]);

        final y2SettlementDebtor = year3.seasonSettlements[1].teamEntries
            .singleWhere((e) => e.teamId == debtorTeamId);
        expect(y2SettlementDebtor.startingDebt, initialY2Debt);
        expect(
          year3.finances.debtByTeam[debtorTeamId.value] ?? 0,
          y2SettlementDebtor.endingDebt,
        );
        expect(
          year3.finances.teamFinances[debtorTeamId.value]?.cash,
          y2SettlementDebtor.endingCash,
        );
        final y2SettlementJson = jsonEncode(
          year3.seasonSettlements[1].toJson(),
        );

        // Codec round-trip + fresh disk reload + bundle transfer verification.
        final roundTripped = GmCareerCodec.decode(GmCareerCodec.encode(year3));
        controller.dispose();
        controllerDisposed = true;

        reloadedController = GmCareerController(storage: storage);
        await reloadedController.loadCareer(slot: slot);
        final reloadedY3 = reloadedController.career!;

        final bundleJson = await reloadedController.exportCareerBundle(
          slot: slot,
        );
        const bundleSlot = 'continuity_bundle';
        await reloadedController.importCareerBundle(
          bundleJson,
          slot: bundleSlot,
        );
        final bundledY3 = reloadedController.career!;

        for (final candidate in [roundTripped, reloadedY3, bundledY3]) {
          expect(
            jsonEncode(candidate.seasonSettlements[0].toJson()),
            y1SettlementJson,
          );
          expect(
            jsonEncode(candidate.seasonSettlements[1].toJson()),
            y2SettlementJson,
          );
          expect(
            candidate.finances.debtByTeam[debtorTeamId.value] ?? 0,
            y2SettlementDebtor.endingDebt,
          );
          final retainedLiability =
              candidate.finances.guaranteedLiabilities[targetLiability.id];
          expect(retainedLiability, isNotNull);
          expect(jsonEncode(retainedLiability!.toJson()), targetLiabilityJson);
          expect(retainedLiability.playerId, targetLiability.playerId);
          expect(retainedLiability.teamId, debtorTeamId);
          expect(retainedLiability.totalObligation, greaterThan(0));
          expect({
            for (final e
                in candidate.marketHistory[0].freeAgentOffers.entries.entries)
              e.key: jsonEncode(e.value.toJson()),
          }, y1OfferPayloads);
          expect({
            for (final e
                in candidate.marketHistory[1].freeAgentOffers.entries.entries)
              e.key: jsonEncode(e.value.toJson()),
          }, y2OfferPayloads);
          for (final fEntry in y1FacilityPayloads.entries) {
            expect(
              jsonEncode(candidate.finances.facilities[fEntry.key]?.toJson()),
              fEntry.value,
            );
          }
        }
      } finally {
        if (!controllerDisposed) {
          controller.dispose();
        }
        reloadedController?.dispose();
      }
    },
  );
}

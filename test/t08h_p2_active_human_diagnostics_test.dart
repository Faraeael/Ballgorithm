import 'dart:convert';
import 'dart:io' as io;
import 'dart:math' as math;

import 'package:basketball_manager/app.dart';
import 'package:basketball_manager/features/career/offseason_overview_screen.dart';
import 'package:basketball_manager/features/season/season_storage.dart';
import 'package:basketball_manager/features/career/career_controller.dart';
import 'package:basketball_manager/features/career/career_storage.dart';
import 'package:basketball_manager/features/career/offseason_clearance_screen.dart';
import 'package:basketball_manager/features/career/regular_season_overview_screen.dart';
import 'package:basketball_manager/features/career/regular_season_results_screen.dart';
import 'package:basketball_manager/features/career/regular_season_schedule_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simulation_core/simulation_core.dart';

const _seeds = [20261028, 1604126146, 987654321, 314159265, 271828182, 8675309];
const _situations = FranchiseSituation.values;
const _evaluator = FreeAgentOfferEvaluator();
const _hardship = HardshipSettlementService();
const _gate = OffseasonReadinessGate();

void main() {
  testWidgets('active human hardship diagnostics across 24 cohorts', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    for (final seed in _seeds) {
      for (final situation in _situations) {
        final result = await _runActiveCohort(tester, seed, situation);
        expect(result.career.league.teams, hasLength(30));
        debugPrint(
          'ACTIVE seed=$seed situation=${situation.jsonValue} '
          'ready=${result.readiness.readyCount}/30 '
          'vacancies=${result.readiness.totalShortage} '
          'human=${result.readiness.humanShortage} '
          'AI=${result.readiness.totalShortage - result.readiness.humanShortage} '
          'hardshipAcquisitions=${result.hardshipAcquisitions} '
          'financialBlocks=${result.financialBlocks} '
          'competitionBlocks=${result.competitionBlocks} '
          'playerRejectionBlocks=${result.playerRejectionBlocks} '
          'ordinaryUsed=${result.ordinaryUsed} '
          'hardshipUsed=${result.hardshipUsed} '
          'totalExceptionUsed=${result.ordinaryUsed + result.hardshipUsed} '
          'maximumRequired=${result.maximumRequired} '
          'humanOffers=${result.humanOffers} '
          'all30=${result.readiness.readyCount == 30}',
        );
        for (final need in result.readiness.teams.where(
          (team) => team.requiredPlayers > 0,
        )) {
          final assessment = result.assessments[need.teamId.value];
          final candidates = _humanCandidates(
            result.career,
            teamId: need.teamId,
            durationOnly: null,
            clearanceOffer: false,
            requireFinancialLegality: false,
          ).take(need.requiredPlayers).toList();
          final salaryTotal = candidates.fold<int>(
            0,
            (sum, candidate) => sum + candidate.salary,
          );
          final overage =
              result.career.finances.capPayrollFor(
                need.teamId,
                result.career.currentYear,
              ) +
              salaryTotal -
              FinancialRules.salaryCap;
          final combinedRequired = overage > 0 ? overage : 0;
          final extraRequired = combinedRequired > need.authorizedCapRelief
              ? combinedRequired - need.authorizedCapRelief
              : 0;
          debugPrint(
            '  BLOCKED ${need.abbreviation}/${need.teamId.value} '
            'standard=${need.standardCount} missing=${need.requiredPlayers} '
            'payrollRoom=${need.capRoom} ordinary=${need.authorizedCapRelief} '
            'requiredOverage=$combinedRequired additionalRequired=$extraRequired '
            'cashAfter=${need.projectedCash - salaryTotal} '
            'acceptable=${candidates.map((offer) => '${offer.playerId.value}:${offer.salary}x${offer.duration}').join(',')} '
            'recordedOutbid=${result.competitionTeamIds.contains(need.teamId.value)} '
            'readiness=${need.blockers.join('; ')} '
            'hardship=${assessment?.blockers.join('; ') ?? 'not assessed'}',
          );
        }
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets(
    'M009-T03 simulates ready careers and recovers game saves',
    (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      const readyCases = [
        (20261028, FranchiseSituation.playIn),
        (20261028, FranchiseSituation.playoff),
        (20261028, FranchiseSituation.contender),
        (987654321, FranchiseSituation.tanking),
        (987654321, FranchiseSituation.playIn),
        (987654321, FranchiseSituation.playoff),
      ];
      const blockedCases = [
        (271828182, FranchiseSituation.tanking),
        (8675309, FranchiseSituation.contender),
      ];
      GmCareer? firstCleared;
      String? firstClearedSave;

      String? scheduleFingerprint;
      final situationCareers = <FranchiseSituation, GmCareer>{};
      for (final (seed, situation) in readyCases) {
        final active = await _runActiveCohort(tester, seed, situation);
        expect(
          active.readiness.status,
          OffseasonReadinessStatus.readyForConfirmation,
          reason: '$seed/${situation.jsonValue}',
        );
        final storage = InMemoryGmCareerStorage({
          'default': GmCareerCodec.encode(active.career),
        });
        final controller = GmCareerController(storage: storage);
        await controller.loadCareer();
        await controller.markOffseasonCleared();
        final cleared = controller.career!;
        expect(
          _gate.evaluate(cleared).status,
          OffseasonReadinessStatus.cleared,
        );
        if (firstCleared == null) {
          firstCleared = cleared;
          firstClearedSave = await storage.read();
          final seasonStorage = InMemorySeasonStorage();
          await tester.pumpWidget(
            BasketballManagerApp(
              league: cleared.league,
              storage: seasonStorage,
              careerStorage: storage,
              careerController: controller,
              seasonMode: true,
            ),
          );
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            find.byKey(const ValueKey('btn-start-regular-season')),
            220,
            scrollable: find
                .descendant(
                  of: find.byKey(const ValueKey('offseason-overview-scroll')),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const ValueKey('btn-start-regular-season')),
          );
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('confirm-start-regular-season')),
            findsOneWidget,
          );
          expect(controller.career!.phase, CareerPhase.openingOffseason);
          await tester.tap(
            find.byKey(const ValueKey('cancel-start-regular-season')),
          );
          await tester.pumpAndSettle();
          expect(await storage.read(), firstClearedSave);
          expect(controller.career!.phase, CareerPhase.openingOffseason);
          await expectLater(
            controller.startRegularSeason(confirmed: false),
            throwsStateError,
          );
          expect(controller.career!.phase, CareerPhase.openingOffseason);
          expect(await storage.read(), firstClearedSave);

          await tester.tap(
            find.byKey(const ValueKey('btn-start-regular-season')),
          );
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const ValueKey('confirm-start-regular-season')),
          );
          await tester.pumpAndSettle();
          final entered = controller.career!;
          expect(entered.phase, CareerPhase.regularSeason);
          expect(entered.regularSeasonState!.gameResults, isEmpty);
          expect(entered.currentYear, cleared.currentYear);
          expect(
            GmCareerCodec.encode(entered),
            GmCareerCodec.encode(
              const RegularSeasonEntryService().start(cleared),
            ),
          );
          expect(find.text('Regular Season'), findsOneWidget);
          expect(find.textContaining('Record: 0–0'), findsOneWidget);
          expect(find.text('Schedule not generated'), findsOneWidget);
          for (final size in const [Size(360, 640), Size(393, 852)]) {
            tester.view.physicalSize = size;
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull, reason: '$size overview');
          }

          final migratedV15 =
              jsonDecode(GmCareerCodec.encode(entered)) as Map<String, dynamic>
                ..['schemaVersion'] = 15;
          (migratedV15['regularSeasonState'] as Map<String, dynamic>).remove(
            'schedule',
          );
          (migratedV15['regularSeasonState'] as Map<String, dynamic>).remove(
            'gameInputSnapshots',
          );
          final migratedCareer = GmCareerCodec.decode(jsonEncode(migratedV15));
          expect(migratedCareer.phase, CareerPhase.regularSeason);
          expect(migratedCareer.regularSeasonState!.schedule, isNull);

          await tester.tap(find.byKey(const ValueKey('btn-generate-schedule')));
          await tester.pumpAndSettle();
          final scheduledCareer = controller.career!;
          situationCareers.putIfAbsent(situation, () => scheduledCareer);
          final schedule = scheduledCareer.regularSeasonState!.schedule!;
          final saveBeforeCancel = await storage.read();
          expect(saveBeforeCancel, isNotNull);
          scheduleFingerprint = schedule.fingerprint;
          final scheduleFreeCareerJson =
              jsonDecode(GmCareerCodec.encode(scheduledCareer))
                  as Map<String, dynamic>;
          (scheduleFreeCareerJson['regularSeasonState']
                  as Map<String, dynamic>)['schedule'] =
              null;
          expect(
            scheduleFreeCareerJson,
            jsonDecode(GmCareerCodec.encode(entered)),
          );
          expect(schedule.rounds, hasLength(82));
          expect(schedule.totalFixtures, 1230);
          expect(
            schedule.fixturesForTeam(entered.userFranchiseId),
            hasLength(82),
          );
          expect(schedule.remainingGamesForTeam(entered.userFranchiseId), 82);
          expect(schedule.completedGamesCount, 0);
          expect(scheduledCareer.regularSeasonState!.gameResults, isEmpty);
          expect(scheduledCareer.currentYear, entered.currentYear);
          expect(find.text('Games scheduled: 82'), findsOneWidget);
          expect(find.text('Upcoming five'), findsOneWidget);
          expect(find.textContaining('Next opponent:'), findsOneWidget);
          expect(
            find.byKey(const ValueKey('btn-view-full-schedule')),
            findsOneWidget,
          );
          await tester.scrollUntilVisible(
            find.text('Simulate Next Round'),
            220,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.ensureVisible(find.text('Simulate Next Round'));
          await tester.tap(find.text('Simulate Next Round'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();
          expect(await storage.read(), saveBeforeCancel);
          expect(controller.career!.regularSeasonState!.gameResults, isEmpty);
          await expectLater(
            controller.simulateNextRegularSeasonRound(
              expectedRoundNumber: 1,
              confirmed: false,
            ),
            throwsStateError,
          );
          expect(await storage.read(), saveBeforeCancel);
          final scheduledSave = await storage.read();
          expect(
            GmCareerCodec.decode(
              scheduledSave!,
            ).regularSeasonState!.schedule!.fingerprint,
            schedule.fingerprint,
          );
          final scheduledV16 = Map<String, dynamic>.from(
            jsonDecode(scheduledSave),
          )..['schemaVersion'] = 16;
          (scheduledV16['regularSeasonState'] as Map<String, dynamic>).remove(
            'gameInputSnapshots',
          );
          final migratedV16 = GmCareerCodec.decode(jsonEncode(scheduledV16));
          final migratedSeason = migratedV16.regularSeasonState!;
          expect(migratedV16.schemaVersion, GmCareer.currentSchemaVersion);
          expect(
            migratedSeason.seasonId,
            scheduledCareer.regularSeasonState!.seasonId,
          );
          expect(migratedSeason.seasonYear, scheduledCareer.currentYear);
          expect(migratedSeason.scheduleSeed, schedule.scheduleSeed);
          expect(migratedSeason.schedule!.fingerprint, schedule.fingerprint);
          expect(
            migratedSeason.openingTeams.map((team) => team.toJson()).toList(),
            scheduledCareer.regularSeasonState!.openingTeams
                .map((team) => team.toJson())
                .toList(),
          );
          expect(migratedSeason.gameResults, isEmpty);
          expect(migratedSeason.completedGames, 0);
          final encodeTimer = Stopwatch()..start();
          final careerSave = GmCareerCodec.encode(scheduledCareer);
          encodeTimer.stop();
          final decodeTimer = Stopwatch()..start();
          final reloadedCareer = GmCareerCodec.decode(careerSave);
          decodeTimer.stop();
          expect(
            reloadedCareer.regularSeasonState!.schedule!.fingerprint,
            schedule.fingerprint,
          );
          expect(careerSave, scheduledSave);
          debugPrint(
            'M009-T02 PERSIST careerBytes=${utf8.encode(careerSave).length} '
            'encodeUs=${encodeTimer.elapsedMicroseconds} '
            'decodeUs=${decodeTimer.elapsedMicroseconds}',
          );

          final corruptedSave =
              jsonDecode(scheduledSave) as Map<String, dynamic>;
          final regularSeasonJson =
              corruptedSave['regularSeasonState'] as Map<String, dynamic>;
          final scheduleJson =
              regularSeasonJson['schedule'] as Map<String, dynamic>;
          final rounds = scheduleJson['rounds'] as List<dynamic>;
          final firstRound = rounds.first as Map<String, dynamic>;
          final firstFixture =
              (firstRound['fixtures'] as List<dynamic>).first
                  as Map<String, dynamic>;
          firstFixture['gameSeed'] = (firstFixture['gameSeed'] as int) + 1;
          expect(
            () => GmCareerCodec.decode(jsonEncode(corruptedSave)),
            throwsFormatException,
          );

          await tester.dragUntilVisible(
            find.byKey(const ValueKey('btn-view-full-schedule')),
            find.byType(ListView).last,
            const Offset(0, -200),
          );
          await tester.tap(
            find.byKey(const ValueKey('btn-view-full-schedule')),
          );
          await tester.pumpAndSettle();
          expect(find.text('Team Schedule'), findsOneWidget);
          final lastFixture = schedule
              .fixturesForTeam(entered.userFranchiseId)
              .last;
          final lastFixtureFinder = find.byKey(
            ValueKey('schedule-fixture-${lastFixture.id}'),
          );
          await tester.scrollUntilVisible(
            lastFixtureFinder,
            350,
            scrollable: find.byType(Scrollable).last,
          );
          expect(lastFixtureFinder, findsOneWidget);
          expect(find.text('Play Game'), findsNothing);
          for (final size in const [Size(360, 640), Size(393, 852)]) {
            tester.view.physicalSize = size;
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull, reason: '$size schedule');
          }
          await tester.pageBack();
          await tester.pumpAndSettle();

          await expectLater(
            controller.startRegularSeason(confirmed: true),
            throwsStateError,
          );
          await expectLater(
            controller.generateRegularSeasonSchedule(),
            throwsStateError,
          );
          expect(controller.career!.phase, CareerPhase.regularSeason);
          expect(await storage.read(), scheduledSave);
          expect(await seasonStorage.read(), isNull);
          final gameplayStorage = InMemoryGmCareerStorage({
            'default': scheduledSave,
          });
          final gameplayController = GmCareerController(
            storage: gameplayStorage,
          );
          await gameplayController.loadCareer();
          await tester.pumpWidget(
            MaterialApp(
              home: RegularSeasonOverviewScreen(controller: gameplayController),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            gameplayController.career!.regularSeasonState!.schedule,
            isNotNull,
          );
          await tester.scrollUntilVisible(
            find.byKey(const ValueKey('btn-view-next-round')),
            220,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.tap(find.text('View Round 1'));
          await tester.pumpAndSettle();
          expect(find.text('Round 1'), findsOneWidget);
          expect(find.text('Scheduled'), findsWidgets);
          for (final size in const [Size(360, 640), Size(393, 852)]) {
            tester.view.physicalSize = size;
            await tester.pumpAndSettle();
            expect(
              tester.takeException(),
              isNull,
              reason: '$size round preview',
            );
          }
          await tester.pageBack();
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            find.text('Simulate Next Round'),
            220,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.tap(find.text('Simulate Next Round'));
          await tester.pumpAndSettle();
          expect(find.text('Simulate Round 1?'), findsOneWidget);
          final confirmedRoundTimer = Stopwatch()..start();
          await tester.tap(find.text('Simulate Next Round').last);
          await tester.pumpAndSettle();
          for (
            var attempt = 0;
            attempt < 600 && gameplayController.isLoading;
            attempt++
          ) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 50)),
            );
            await tester.pump();
          }
          expect(gameplayController.isLoading, isFalse);
          await tester.pumpAndSettle();
          expect(gameplayController.errorMessage, isNull);
          confirmedRoundTimer.stop();
          expect(
            gameplayController.career!.regularSeasonState!.gameResults,
            hasLength(15),
          );
          final engineTimer = Stopwatch()..start();
          final engineRound = const RegularSeasonRoundService()
              .simulateNextRound(scheduledCareer, expectedRoundNumber: 1);
          engineTimer.stop();
          expect(
            GmCareerCodec.encode(gameplayController.career!),
            GmCareerCodec.encode(engineRound),
          );
          final playedSave = await gameplayStorage.read();
          final legacyV17 = Map<String, dynamic>.from(
            jsonDecode(playedSave!) as Map,
          )..['schemaVersion'] = 17;
          final legacySeason =
              legacyV17['regularSeasonState'] as Map<String, dynamic>;
          legacySeason.remove('gameInputSnapshots');
          final legacyResults =
              legacySeason['gameResults'] as Map<String, dynamic>;
          for (final rawResult in legacyResults.values) {
            final result = rawResult as Map<String, dynamic>;
            result.remove('inputEvidence');
            result.remove('fingerprintVersion');
            result.remove('coreEngineVersion');
            result.remove('leagueSchemaVersion');
          }
          final beforeMigrationResults =
              gameplayController.career!.regularSeasonState!.gameResults;
          final migratedV17 = GmCareerCodec.decode(jsonEncode(legacyV17));
          expect(migratedV17.schemaVersion, GmCareer.currentSchemaVersion);
          expect(migratedV17.regularSeasonState!.gameResults, hasLength(15));
          expect(
            migratedV17.regularSeasonState!.gameInputSnapshots,
            hasLength(1),
          );
          expect(migratedV17.regularSeasonState!.nextUnfinishedRoundNumber, 2);
          for (final entry in beforeMigrationResults.entries) {
            final migratedResult =
                migratedV17.regularSeasonState!.gameResults[entry.key]!;
            expect(
              migratedResult.inputFingerprint,
              entry.value.inputFingerprint,
            );
            expect(
              migratedResult.summary.toJson(),
              entry.value.summary.toJson(),
            );
          }
          final tamperedResultSave =
              jsonDecode(playedSave) as Map<String, dynamic>;
          final tamperedSeason =
              tamperedResultSave['regularSeasonState'] as Map<String, dynamic>;
          final resultRecords =
              tamperedSeason['gameResults'] as Map<String, dynamic>;
          final firstResult =
              resultRecords.values.first as Map<String, dynamic>;
          final firstSummary = firstResult['summary'] as Map<String, dynamic>;
          firstSummary['homeScore'] = (firstSummary['homeScore'] as int) + 1;
          expect(
            () => GmCareerCodec.decode(jsonEncode(tamperedResultSave)),
            throwsFormatException,
          );
          final tamperedFingerprintSave =
              jsonDecode(playedSave) as Map<String, dynamic>;
          final fingerprintSeason =
              tamperedFingerprintSave['regularSeasonState']
                  as Map<String, dynamic>;
          final fingerprintResults =
              fingerprintSeason['gameResults'] as Map<String, dynamic>;
          final fingerprintResult =
              fingerprintResults.values.first as Map<String, dynamic>;
          fingerprintResult['inputFingerprint'] = List.filled(64, '0').join();
          expect(
            () => GmCareerCodec.decode(jsonEncode(tamperedFingerprintSave)),
            throwsFormatException,
          );
          await expectLater(
            gameplayController.simulateNextRegularSeasonRound(
              expectedRoundNumber: 1,
              confirmed: true,
            ),
            throwsStateError,
          );
          expect(await gameplayStorage.read(), playedSave);
          await gameplayController.loadCareer();
          expect(
            gameplayController.career!.regularSeasonState!.gameResults,
            hasLength(15),
          );
          final roundOneState = gameplayController.career!.regularSeasonState!;
          expect(roundOneState.completedRounds, 1);
          expect(roundOneState.remainingGames, 1215);
          expect(roundOneState.nextUnfinishedRoundNumber, 2);
          expect(GmCareerCodec.encode(gameplayController.career!), playedSave);
          _logRoundMetrics(
            seed,
            roundOneState,
            entered.userFranchiseId,
            confirmedRoundTimer.elapsedMilliseconds,
            engineTimer.elapsedMilliseconds,
          );
          final postPromotionStorage = _CommitThenFailCareerStorage(
            InMemoryGmCareerStorage({'default': playedSave}),
          )..failNextWrite = true;
          final postPromotionController = GmCareerController(
            storage: postPromotionStorage,
          );
          await postPromotionController.loadCareer();
          await expectLater(
            _pumpCommand(
              tester,
              postPromotionController.simulateNextRegularSeasonRound(
                expectedRoundNumber: 2,
                confirmed: true,
              ),
            ),
            throwsA(isA<GmCareerStorageException>()),
          );
          expect(postPromotionController.draftRecoveryRequired, isTrue);
          expect(
            postPromotionController.career!.regularSeasonState!.gameResults,
            hasLength(15),
          );
          await postPromotionController.loadCareer();
          expect(
            postPromotionController.career!.regularSeasonState!.gameResults,
            hasLength(30),
          );
          final recoveredPostPromotionSave = await postPromotionStorage.read();
          expect(
            GmCareerCodec.encode(postPromotionController.career!),
            recoveredPostPromotionSave,
          );
          postPromotionController.dispose();
          await tester.pumpWidget(
            MaterialApp(
              home: RegularSeasonOverviewScreen(controller: gameplayController),
            ),
          );
          await tester.pumpAndSettle();
          await tester.drag(
            find.byType(Scrollable).first,
            const Offset(0, 1000),
          );
          await tester.pumpAndSettle();
          expect(find.byType(RegularSeasonOverviewScreen), findsOneWidget);
          expect(find.text('Regular Season'), findsOneWidget);
          final humanStanding = gameplayController
              .career!
              .regularSeasonState!
              .standings
              .table[entered.userFranchiseId.value]!;
          final recordText =
              'Record: ${humanStanding.wins}–${humanStanding.losses}';
          final renderedRecordTexts = tester
              .widgetList<Text>(find.byType(Text))
              .map((widget) => widget.data)
              .where((text) => text?.startsWith('Record:') ?? false)
              .toList();
          expect(
            renderedRecordTexts,
            [recordText],
            reason: 'Rendered record labels: $renderedRecordTexts',
          );
          await tester.scrollUntilVisible(
            find.text('Last game'),
            220,
            scrollable: find.byType(Scrollable).first,
          );
          expect(find.text('Last game'), findsOneWidget);
          await tester.scrollUntilVisible(
            find.text('View Box Score'),
            220,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.ensureVisible(find.text('View Box Score'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('View Box Score'));
          for (final size in const [Size(360, 640), Size(393, 852)]) {
            tester.view.physicalSize = size;
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull, reason: '$size box score');
          }
          await tester.pumpAndSettle();
          expect(find.text('Box Score'), findsOneWidget);
          expect(find.textContaining('PTS'), findsWidgets);
          await tester.pageBack();
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('View League Results'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('View League Results'));
          await tester.pumpAndSettle();
          expect(find.text('League Results'), findsOneWidget);
          for (final size in const [Size(360, 640), Size(393, 852)]) {
            tester.view.physicalSize = size;
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull, reason: '$size results');
          }
          await tester.pageBack();
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('View Standings'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('View Standings'));
          await tester.pumpAndSettle();
          expect(find.text('Standings'), findsOneWidget);
          expect(find.textContaining('GP '), findsWidgets);
          for (final size in const [Size(360, 640), Size(393, 852)]) {
            tester.view.physicalSize = size;
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull, reason: '$size standings');
          }
          await tester.pageBack();
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            find.byKey(const ValueKey('btn-view-full-schedule')),
            220,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.ensureVisible(
            find.byKey(const ValueKey('btn-view-full-schedule')),
          );
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const ValueKey('btn-view-full-schedule')),
          );
          await tester.pumpAndSettle();
          final humanFixture = schedule.rounds.first.fixtures.firstWhere(
            (fixture) =>
                fixture.homeTeamId == entered.userFranchiseId ||
                fixture.awayTeamId == entered.userFranchiseId,
          );
          final humanGame = gameplayController
              .career!
              .regularSeasonState!
              .gameResults[humanFixture.id]!;
          final ownScore = humanFixture.homeTeamId == entered.userFranchiseId
              ? humanGame.summary.homeScore
              : humanGame.summary.awayScore;
          final opponentScore =
              humanFixture.homeTeamId == entered.userFranchiseId
              ? humanGame.summary.awayScore
              : humanGame.summary.homeScore;
          expect(find.text('Final $ownScore–$opponentScore'), findsOneWidget);
          await tester.pageBack();
          await tester.pumpAndSettle();
          final concurrent = await _pumpCommand(
            tester,
            Future.wait<Object?>([
              gameplayController
                  .simulateNextRegularSeasonRound(
                    expectedRoundNumber: 2,
                    confirmed: true,
                  )
                  .then<Object?>((_) => null, onError: (Object error) => error),
              gameplayController
                  .simulateNextRegularSeasonRound(
                    expectedRoundNumber: 2,
                    confirmed: true,
                  )
                  .then<Object?>((_) => null, onError: (Object error) => error),
            ]),
          );
          expect(concurrent.whereType<StateError>(), hasLength(1));
          expect(
            gameplayController.career!.regularSeasonState!.gameResults,
            hasLength(30),
          );
          expect(gameplayController.career!.currentYear, entered.currentYear);
          gameplayStorage.shouldThrowOnWrite = true;
          await expectLater(
            _pumpCommand(
              tester,
              gameplayController.simulateNextRegularSeasonRound(
                expectedRoundNumber: 3,
                confirmed: true,
              ),
            ),
            throwsA(isA<GmCareerStorageException>()),
          );
          expect(gameplayController.draftRecoveryRequired, isTrue);
          expect(
            gameplayController.career!.regularSeasonState!.gameResults,
            hasLength(30),
          );
          gameplayStorage.shouldThrowOnWrite = false;
          await gameplayController.loadCareer();
          expect(gameplayController.draftRecoveryRequired, isFalse);
          expect(
            gameplayController.career!.regularSeasonState!.gameResults,
            hasLength(30),
          );
          final thirdRoundTimer = Stopwatch()..start();
          await _pumpCommand(
            tester,
            gameplayController.simulateNextRegularSeasonRound(
              expectedRoundNumber: 3,
              confirmed: true,
            ),
          );
          thirdRoundTimer.stop();
          final threeRoundCareer = gameplayController.career!;
          expect(
            threeRoundCareer.regularSeasonState!.gameResults,
            hasLength(45),
          );
          expect(threeRoundCareer.currentYear, entered.currentYear);
          debugPrint(
            'T03 seed=$seed rounds=3 games=45 '
            'round3Ms=${thirdRoundTimer.elapsedMilliseconds} '
            'record=${threeRoundCareer.regularSeasonState!.standings.table[entered.userFranchiseId.value]!.wins}-'
            '${threeRoundCareer.regularSeasonState!.standings.table[entered.userFranchiseId.value]!.losses}',
          );
          await _runFullSeasonReliability(tester, scheduledCareer);
          gameplayController.dispose();
          await tester.pumpWidget(const SizedBox.shrink());
          controller.dispose();

          final failureSeasonStorage = InMemorySeasonStorage();
          final failureStorage = _CommitThenFailCareerStorage(
            InMemoryGmCareerStorage({'default': firstClearedSave}),
          )..failNextWrite = true;
          final failureController = GmCareerController(storage: failureStorage);
          await failureController.loadCareer();
          await tester.pumpWidget(
            BasketballManagerApp(
              league: cleared.league,
              storage: failureSeasonStorage,
              careerStorage: failureStorage,
              careerController: failureController,
              seasonMode: true,
            ),
          );
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            find.byKey(const ValueKey('btn-start-regular-season')),
            220,
            scrollable: find
                .descendant(
                  of: find.byKey(const ValueKey('offseason-overview-scroll')),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const ValueKey('btn-start-regular-season')),
          );
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const ValueKey('confirm-start-regular-season')),
          );
          await tester.pumpAndSettle();
          expect(failureController.career!.phase, CareerPhase.openingOffseason);
          expect(failureController.draftRecoveryRequired, isTrue);
          final promotedSave = await failureStorage.read();
          expect(
            GmCareerCodec.decode(promotedSave!).phase,
            CareerPhase.regularSeason,
          );
          await tester.scrollUntilVisible(
            find.byKey(const ValueKey('btn-season-entry-reload')),
            220,
            scrollable: find
                .descendant(
                  of: find.byKey(const ValueKey('offseason-overview-scroll')),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const ValueKey('btn-season-entry-reload')),
          );
          await tester.pumpAndSettle();
          expect(failureController.career!.phase, CareerPhase.regularSeason);
          expect(failureController.draftRecoveryRequired, isFalse);
          expect(
            failureController.career!.regularSeasonState!.seasonId,
            entered.regularSeasonState!.seasonId,
          );
          expect(
            failureController.career!.freeAgentPool.acquisitions.entries.length,
            cleared.freeAgentPool.acquisitions.entries.length,
          );
          expect(
            failureController.career!.finances.contracts.keys.toSet(),
            cleared.finances.contracts.keys.toSet(),
          );
          expect(await failureSeasonStorage.read(), isNull);
          expect(GmCareerCodec.encode(failureController.career!), promotedSave);
          await expectLater(
            failureController.startRegularSeason(confirmed: true),
            throwsStateError,
          );
          expect(await failureStorage.read(), promotedSave);
          failureStorage.failBeforePromotionNextWrite = true;
          await tester.tap(find.byKey(const ValueKey('btn-generate-schedule')));
          await tester.pumpAndSettle();
          expect(
            failureController.career!.regularSeasonState!.schedule,
            isNull,
          );
          expect(failureController.draftRecoveryRequired, isTrue);
          expect(await failureStorage.read(), promotedSave);
          await tester.tap(find.byKey(const ValueKey('btn-schedule-reload')));
          await tester.pumpAndSettle();
          expect(failureController.draftRecoveryRequired, isFalse);
          expect(
            failureController.career!.regularSeasonState!.schedule,
            isNull,
          );

          failureStorage.failNextWrite = true;
          await tester.tap(find.byKey(const ValueKey('btn-generate-schedule')));
          await tester.pumpAndSettle();
          expect(
            failureController.career!.regularSeasonState!.schedule,
            isNull,
          );
          expect(failureController.draftRecoveryRequired, isTrue);
          final promotedScheduleSave = await failureStorage.read();
          final persistedSchedule = GmCareerCodec.decode(
            promotedScheduleSave!,
          ).regularSeasonState!.schedule!;
          await tester.tap(find.byKey(const ValueKey('btn-schedule-reload')));
          await tester.pumpAndSettle();
          final recoveredCareer = failureController.career!;
          expect(failureController.draftRecoveryRequired, isFalse);
          expect(
            recoveredCareer.regularSeasonState!.schedule!.fingerprint,
            persistedSchedule.fingerprint,
          );
          expect(GmCareerCodec.encode(recoveredCareer), promotedScheduleSave);
          expect(
            GmCareerCodec.encode(recoveredCareer),
            GmCareerCodec.encode(
              const RegularSeasonScheduleService().generate(entered),
            ),
          );
          expect(recoveredCareer.currentYear, entered.currentYear);
          expect(recoveredCareer.regularSeasonState!.gameResults, isEmpty);
          final writesBeforeDuplicate = failureStorage.writes;
          await expectLater(
            failureController.generateRegularSeasonSchedule(),
            throwsStateError,
          );
          expect(failureStorage.writes, writesBeforeDuplicate);
          expect(await failureStorage.read(), promotedScheduleSave);
          expect(await failureSeasonStorage.read(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          failureController.dispose();
        } else {
          await controller.startRegularSeason(confirmed: true);
          final entered = controller.career!;
          expect(entered.phase, CareerPhase.regularSeason);
          expect(entered.regularSeasonState!.gameResults, isEmpty);
          expect(entered.regularSeasonState!.scheduleSeed, seed);
          expect(
            GmCareerCodec.encode(entered),
            GmCareerCodec.encode(
              const RegularSeasonEntryService().start(cleared),
            ),
          );
          await controller.generateRegularSeasonSchedule();
          final schedule = controller.career!.regularSeasonState!.schedule!;
          scheduleFingerprint = schedule.fingerprint;
          expect(schedule.rounds, hasLength(82));
          expect(schedule.totalFixtures, 1230);
          expect(
            schedule.fixturesForTeam(entered.userFranchiseId),
            hasLength(82),
          );
          expect(
            GmCareerCodec.decode(
              (await storage.read())!,
            ).regularSeasonState!.schedule!.fingerprint,
            schedule.fingerprint,
          );
          final scheduledCareer = controller.career!;
          situationCareers.putIfAbsent(situation, () => scheduledCareer);
          final roundTimer = Stopwatch()..start();
          await _pumpCommand(
            tester,
            controller.simulateNextRegularSeasonRound(
              expectedRoundNumber: 1,
              confirmed: true,
            ),
          );
          roundTimer.stop();
          await controller.loadCareer();
          final roundState = controller.career!.regularSeasonState!;
          expect(roundState.gameResults, hasLength(15));
          expect(roundState.completedRounds, 1);
          expect(roundState.remainingGames, 1215);
          expect(roundState.nextUnfinishedRoundNumber, 2);
          expect(controller.career!.currentYear, entered.currentYear);
          final engineTimer = Stopwatch()..start();
          final engineRound = const RegularSeasonRoundService()
              .simulateNextRound(scheduledCareer, expectedRoundNumber: 1);
          engineTimer.stop();
          expect(
            GmCareerCodec.encode(controller.career!),
            GmCareerCodec.encode(engineRound),
          );
          _logRoundMetrics(
            seed,
            roundState,
            entered.userFranchiseId,
            roundTimer.elapsedMilliseconds,
            engineTimer.elapsedMilliseconds,
          );
          final humanRow =
              roundState.standings.table[entered.userFranchiseId.value]!;
          debugPrint(
            'T03 seed=$seed situation=${situation.jsonValue} '
            'human=${humanRow.wins}-${humanRow.losses} '
            'reloadResults=${roundState.gameResults.length}',
          );
          controller.dispose();
        }
        debugPrint(
          'M009-T02 READY seed=$seed situation=${situation.jsonValue} '
          'phase=regularSeason scheduleSeed=$seed rounds=82 fixtures=1230 '
          'fingerprint=$scheduleFingerprint gameplay=round-1-verified',
        );
      }
      _reportStartingSituationSeasons(situationCareers);

      for (final (seed, situation) in blockedCases) {
        final active = await _runActiveCohort(tester, seed, situation);
        expect(active.readiness.readyCount, lessThan(30));
        expect(
          () => const RegularSeasonEntryService().start(active.career),
          throwsA(isA<RegularSeasonEntryBlocked>()),
        );
        final blockedStorage = InMemoryGmCareerStorage({
          'default': GmCareerCodec.encode(active.career),
        });
        final blockedController = GmCareerController(storage: blockedStorage);
        await blockedController.loadCareer();
        final blockedSave = await blockedStorage.read();
        await expectLater(
          blockedController.generateRegularSeasonSchedule(),
          throwsStateError,
        );
        expect(await blockedStorage.read(), blockedSave);
        expect(blockedController.career!.regularSeasonState, isNull);
        await expectLater(
          blockedController.simulateNextRegularSeasonRound(
            expectedRoundNumber: 1,
            confirmed: true,
          ),
          throwsStateError,
        );
        expect(await blockedStorage.read(), blockedSave);
        await blockedController.loadCareer();
        await tester.pumpWidget(
          MaterialApp(
            home: GmOffseasonOverviewScreen(controller: blockedController),
          ),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('btn-start-regular-season')),
          220,
          scrollable: find
              .descendant(
                of: find.byKey(const ValueKey('offseason-overview-scroll')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(find.text('Season Start Blocked'), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const ValueKey('btn-start-regular-season')),
              )
              .onPressed,
          isNull,
        );
        expect(blockedController.career!.phase, CareerPhase.openingOffseason);
        await tester.pumpWidget(const SizedBox.shrink());
        blockedController.dispose();
        debugPrint(
          'M009-T01 BLOCKED seed=$seed situation=${situation.jsonValue} '
          'ready=${active.readiness.readyCount}/30 '
          'vacancies=${active.readiness.totalShortage}',
        );
      }
      expect(firstCleared, isNotNull);
      expect(firstClearedSave, isNotNull);
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
    timeout: const Timeout(Duration(minutes: 60)),
  );
}

Future<_ActiveResult> _runActiveCohort(
  WidgetTester tester,
  int seed,
  FranchiseSituation situation,
) async {
  var career = GmCareer.fromSetupResult(
    const CareerSetupService().generate(
      CareerSetupRequest(
        selectedTeamId: const TeamId('team-1'),
        selectedSituation: situation,
        seed: seed,
      ),
    ),
    id: 't08h-p2-active-$seed-${situation.jsonValue}',
  );
  career = _completeDraft(career);
  career = _completeAiRookieDecisions(career);
  final controller = GmCareerController(
    storage: InMemoryGmCareerStorage({'default': GmCareerCodec.encode(career)}),
  );
  await controller.loadCareer();
  try {
    for (var round = 0; round < 2; round++) {
      await controller.startFreeAgencyRound();
      await _submitHumanMarketOffers(controller);
      await controller.prepareFreeAgencyResolution();
      await controller.resolveFreeAgencyRound();
    }
    await controller.startOffseasonClearance();
    await _submitHumanClearanceOffers(controller);
    await controller.prepareOffseasonClearance();
    await controller.resolveOffseasonClearance();

    final beforeHardship = controller.career!;
    final assessments = <String, HardshipTeamAssessment>{
      for (final team in beforeHardship.league.teams)
        team.id.value: _hardship.assessTeam(beforeHardship, team.id),
    };
    final humanAssessment = assessments[beforeHardship.userFranchiseId.value]!;
    if (beforeHardship.offseasonClearance.status ==
            OffseasonClearanceStatus.complete &&
        beforeHardship.hardshipSettlement.status ==
            HardshipSettlementStatus.notStarted &&
        _gate.evaluate(beforeHardship).belowMinimumCount > 0) {
      await tester.pumpWidget(
        MaterialApp(home: GmOffseasonClearanceScreen(controller: controller)),
      );
      if (humanAssessment.eligible) {
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('confirm-human-hardship')),
          220,
        );
        await tester.tap(find.byKey(const ValueKey('confirm-human-hardship')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('approve-human-hardship')));
        await tester.pumpAndSettle();
      } else {
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('prepare-ai-hardship')),
          220,
        );
        await tester.tap(find.byKey(const ValueKey('prepare-ai-hardship')));
        await tester.pumpAndSettle();
      }
      if (controller.career!.hardshipSettlement.isResolvable) {
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('resolve-hardship')),
          220,
        );
        await tester.tap(find.byKey(const ValueKey('resolve-hardship')));
        await tester.pumpAndSettle();
      }
    }

    final finalCareer = controller.career!;
    expect(controller.errorMessage, isNull);
    expect(finalCareer.freeAgentMarket.completedRounds, 2);
    expect(
      finalCareer.offseasonClearance.status,
      OffseasonClearanceStatus.complete,
    );
    expect(finalCareer.currentYear, 1);
    expect(
      finalCareer.hardshipSettlement.offers.any(
        (offer) => offer.teamId == finalCareer.userFranchiseId,
      ),
      humanAssessment.eligible,
    );
    final readiness = _gate.evaluate(finalCareer);
    final blockedIds = {
      for (final team in readiness.teams)
        if (team.requiredPlayers > 0) team.teamId.value,
    };
    final outbidTeams = <String>{
      for (final round in finalCareer.freeAgentMarket.roundHistory)
        for (final outcome in round.outcomes)
          for (final result in outcome.results)
            if (result.outcome == FreeAgentMarketOfferOutcome.outbid)
              result.teamId.value,
      for (final outcome in finalCareer.offseasonClearance.outcomes)
        for (final result in outcome.results)
          if (result.outcome == FreeAgentMarketOfferOutcome.outbid)
            result.teamId.value,
      for (final outcome in finalCareer.hardshipSettlement.outcomes)
        for (final result in outcome.results)
          if (result.outcome == FreeAgentMarketOfferOutcome.outbid)
            result.teamId.value,
    };
    final rejectedTeams = <String>{
      for (final round in finalCareer.freeAgentMarket.roundHistory)
        for (final outcome in round.outcomes)
          for (final result in outcome.results)
            if (result.outcome == FreeAgentMarketOfferOutcome.rejected)
              result.teamId.value,
      for (final outcome in finalCareer.offseasonClearance.outcomes)
        for (final result in outcome.results)
          if (result.outcome == FreeAgentMarketOfferOutcome.rejected)
            result.teamId.value,
      for (final outcome in finalCareer.hardshipSettlement.outcomes)
        for (final result in outcome.results)
          if (result.outcome == FreeAgentMarketOfferOutcome.rejected)
            result.teamId.value,
    };
    var maximumRequired = finalCareer.hardshipSettlement.authorizations
        .fold<int>(0, (maximum, authorization) {
          final required =
              authorization.existingOrdinaryRelief +
              authorization.additionalAmount;
          return required > maximum ? required : maximum;
        });
    final financiallyBlocked = <String>{};
    final competitionBlocked = <String>{};
    final playerRejected = <String>{};
    for (final teamId in blockedIds) {
      final assessment = assessments[teamId];
      if (assessment != null &&
          assessment.blockers.any(
            (reason) =>
                reason.contains('cash insolvent') ||
                reason.contains('No willing contract fits cash') ||
                reason.contains('fit the approved ceiling'),
          )) {
        financiallyBlocked.add(teamId);
      }
      final need = readiness.teams.firstWhere(
        (team) => team.teamId.value == teamId,
      );
      final candidates = _humanCandidates(
        finalCareer,
        teamId: need.teamId,
        durationOnly: null,
        clearanceOffer: false,
        requireFinancialLegality: false,
      ).take(need.requiredPlayers);
      final salaryTotal = candidates.fold<int>(
        0,
        (sum, candidate) => sum + candidate.salary,
      );
      final overage =
          finalCareer.finances.capPayrollFor(
            need.teamId,
            finalCareer.currentYear,
          ) +
          salaryTotal -
          FinancialRules.salaryCap;
      final required = overage > 0 ? overage : 0;
      if (required > FinancialRules.maximumCombinedHardshipOverage ||
          need.projectedCash - salaryTotal < 0) {
        financiallyBlocked.add(teamId);
      }
      if (required > maximumRequired) maximumRequired = required;
      if (outbidTeams.contains(teamId)) competitionBlocked.add(teamId);
      if (rejectedTeams.contains(teamId)) playerRejected.add(teamId);
    }
    return _ActiveResult(
      career: finalCareer,
      readiness: readiness,
      assessments: assessments,
      hardshipAcquisitions: finalCareer
          .freeAgentPool
          .acquisitions
          .entries
          .values
          .where((item) => item.origin == AcquisitionOrigin.hardship)
          .length,
      financialBlocks: financiallyBlocked.length,
      competitionBlocks: competitionBlocked.length,
      competitionTeamIds: outbidTeams.intersection(blockedIds),
      playerRejectionBlocks: playerRejected.length,
      maximumRequired: maximumRequired,
      ordinaryUsed: finalCareer.league.teams.fold<int>(0, (sum, team) {
        final capException = finalCareer.finances
            .financesFor(team.id)
            .capException;
        final overCap =
            finalCareer.finances.capPayrollFor(
              team.id,
              finalCareer.currentYear,
            ) -
            FinancialRules.salaryCap;
        final hardshipUsed =
            finalCareer.hardshipSettlement
                .authorizationFor(team.id)
                ?.usedAmount ??
            0;
        return sum + (overCap - hardshipUsed).clamp(0, capException).toInt();
      }),
      hardshipUsed: finalCareer.hardshipSettlement.authorizations.fold<int>(
        0,
        (sum, record) => sum + record.usedAmount,
      ),
      humanOffers:
          finalCareer.freeAgentMarket.roundHistory
              .expand((round) => round.humanOffers)
              .where((offer) => offer.teamId == finalCareer.userFranchiseId)
              .length +
          finalCareer.offseasonClearance.humanOffers.length +
          finalCareer.hardshipSettlement.offers
              .where((offer) => offer.teamId == finalCareer.userFranchiseId)
              .length,
    );
  } finally {
    controller.dispose();
  }
}

Future<void> _submitHumanMarketOffers(GmCareerController controller) async {
  var career = controller.career!;
  final missing =
      RosterRules.minRegularSeasonStandard -
      career.userTeam.roster.standardCount;
  if (missing <= 0) return;
  final candidates = _humanCandidates(
    career,
    teamId: career.userFranchiseId,
    durationOnly: null,
    clearanceOffer: false,
  );
  var submitted = 0;
  for (final candidate in candidates) {
    if (submitted >= missing) break;
    career = controller.career!;
    if (_evaluator
            .evaluate(
              career: career,
              teamId: career.userFranchiseId,
              freeAgentId: candidate.playerId,
              category: RosterCategory.standard,
              durationYears: candidate.duration,
              agreedFirstYearSalary: candidate.salary,
            )
            .status !=
        FreeAgentOfferStatus.acceptable) {
      continue;
    }
    try {
      await controller.stageFreeAgentOffer(
        freeAgentId: candidate.playerId,
        category: RosterCategory.standard,
        durationYears: candidate.duration,
        firstYearSalary: candidate.salary,
      );
      submitted++;
    } on DomainValidationException {
      // Skip a candidate when a prior reservation makes its offer illegal.
    }
  }
}

Future<void> _submitHumanClearanceOffers(GmCareerController controller) async {
  var career = controller.career!;
  final missing =
      RosterRules.minRegularSeasonStandard -
      career.userTeam.roster.standardCount;
  if (missing <= 0) return;
  final candidates = _humanCandidates(
    career,
    teamId: career.userFranchiseId,
    durationOnly: 1,
    clearanceOffer: true,
  );
  var submitted = 0;
  for (final candidate in candidates) {
    if (submitted >= missing) break;
    career = controller.career!;
    if (_evaluator
            .evaluate(
              career: career,
              teamId: career.userFranchiseId,
              freeAgentId: candidate.playerId,
              category: RosterCategory.standard,
              durationYears: 1,
              agreedFirstYearSalary: candidate.salary,
              clearanceOffer: true,
            )
            .status !=
        FreeAgentOfferStatus.acceptable) {
      continue;
    }
    try {
      await controller.stageClearanceOffer(
        freeAgentId: candidate.playerId,
        durationYears: 1,
        firstYearSalary: candidate.salary,
      );
      submitted++;
    } on DomainValidationException {
      // Skip a candidate when a prior reservation makes its offer illegal.
    }
  }
}

List<_HumanCandidate> _humanCandidates(
  GmCareer career, {
  required TeamId teamId,
  required int? durationOnly,
  required bool clearanceOffer,
  bool requireFinancialLegality = true,
}) {
  final candidates = <_HumanCandidate>[];
  for (final entry in career.freeAgentPool.entries) {
    if (career.freeAgentOffers.remainingAttempts(
          teamId: teamId,
          playerId: entry.id,
          seasonYear: career.currentYear,
        ) <=
        0) {
      continue;
    }
    final durations = durationOnly == null
        ? Iterable<int>.generate(
            FinancialRules.maxDurationForCategory(RosterCategory.standard),
            (index) => index + 1,
          )
        : [durationOnly];
    _HumanCandidate? cheapest;
    for (final duration in durations) {
      final maxSalary = FreeAgentMarketValueService.maxYearOneForDuration(
        duration,
      );
      var low = FinancialRules.minimumSalary;
      var high = maxSalary + 1;
      while (low < high) {
        final salary = low + (high - low) ~/ 2;
        final willingness = _evaluator.evaluateWillingness(
          career: career,
          teamId: teamId,
          freeAgentId: entry.id,
          category: RosterCategory.standard,
          durationYears: duration,
          salary: salary,
        );
        if (willingness.accepts) {
          high = salary;
        } else {
          low = salary + 1;
        }
      }
      if (low > maxSalary) continue;
      if (requireFinancialLegality) {
        final decision = _evaluator.evaluate(
          career: career,
          teamId: teamId,
          freeAgentId: entry.id,
          category: RosterCategory.standard,
          durationYears: duration,
          agreedFirstYearSalary: low,
          clearanceOffer: clearanceOffer,
        );
        if (!decision.isAcceptable) continue;
      }
      final candidate = _HumanCandidate(entry.id, low, duration);
      if (cheapest == null || candidate.compareTo(cheapest) < 0) {
        cheapest = candidate;
      }
    }
    if (cheapest != null) candidates.add(cheapest);
  }
  candidates.sort((a, b) => a.compareTo(b));
  return candidates;
}

GmCareer _completeDraft(GmCareer career) {
  const draft = DraftExecutionService();
  var current = draft.startDraft(career);
  while (!current.draftExecutionState.isCompleted) {
    current =
        current.draftExecutionState.isHumanTurn(
          order: current.draftOrder,
          userTeamId: current.userFranchiseId,
        )
        ? draft.makeHumanSelection(
            career: current,
            prospectId: current.draftExecutionState
                .availableProspects(current.draftClass)
                .first
                .id,
          )
        : draft.executeAiSelection(current);
  }
  return current;
}

GmCareer _completeAiRookieDecisions(GmCareer career) {
  const rookies = RookieAiSigningService();
  var current = rookies.initialize(career);
  while (rookies.pendingRights(current).isNotEmpty) {
    current = rookies.applyNextDecision(current);
  }
  return current;
}

final class _HumanCandidate implements Comparable<_HumanCandidate> {
  const _HumanCandidate(this.playerId, this.salary, this.duration);

  final PlayerId playerId;
  final int salary;
  final int duration;

  int get totalSalary => FinancialRules.standardSchedule(
    salary,
    duration,
  ).fold<int>(0, (sum, amount) => sum + amount);

  @override
  int compareTo(_HumanCandidate other) {
    var order = salary.compareTo(other.salary);
    if (order != 0) return order;
    order = totalSalary.compareTo(other.totalSalary);
    if (order != 0) return order;
    order = duration.compareTo(other.duration);
    return order != 0 ? order : playerId.value.compareTo(other.playerId.value);
  }
}

final class _ActiveResult {
  const _ActiveResult({
    required this.career,
    required this.readiness,
    required this.assessments,
    required this.hardshipAcquisitions,
    required this.financialBlocks,
    required this.competitionBlocks,
    required this.competitionTeamIds,
    required this.playerRejectionBlocks,
    required this.ordinaryUsed,
    required this.hardshipUsed,
    required this.maximumRequired,
    required this.humanOffers,
  });

  final GmCareer career;
  final OffseasonReadinessResult readiness;
  final Map<String, HardshipTeamAssessment> assessments;
  final int hardshipAcquisitions;
  final int financialBlocks;
  final int competitionBlocks;
  final Set<String> competitionTeamIds;
  final int playerRejectionBlocks;
  final int ordinaryUsed;
  final int hardshipUsed;
  final int maximumRequired;
  final int humanOffers;
}

final class _CommitThenFailCareerStorage implements GmCareerStorage {
  _CommitThenFailCareerStorage(this.delegate);

  final InMemoryGmCareerStorage delegate;
  bool failNextWrite = false;
  bool failBeforePromotionNextWrite = false;
  int writes = 0;

  @override
  Future<String?> read({String slot = 'default'}) => delegate.read(slot: slot);

  @override
  Future<void> write(String data, {String slot = 'default'}) async {
    writes++;
    if (failBeforePromotionNextWrite) {
      failBeforePromotionNextWrite = false;
      throw const GmCareerStorageException('Injected pre-promotion failure');
    }
    await delegate.write(data, slot: slot);
    if (failNextWrite) {
      failNextWrite = false;
      throw const GmCareerStorageException('Injected post-promotion failure');
    }
  }

  @override
  Future<void> clear({String slot = 'default'}) => delegate.clear(slot: slot);

  @override
  Future<bool> hasSave({String slot = 'default'}) =>
      delegate.hasSave(slot: slot);
}

void _logRoundMetrics(
  int seed,
  RegularSeasonState state,
  TeamId humanTeamId,
  int roundTransactionMilliseconds,
  int engineMilliseconds,
) {
  final games = state.gameResults.values.toList();
  final lines = games
      .expand((game) => game.summary.playerLines.values)
      .toList();
  int total(int Function(SeasonPlayerGameLine line) select) =>
      lines.fold(0, (sum, line) => sum + select(line));
  double percentage(int made, int attempted) =>
      attempted == 0 ? 0 : 100 * made / attempted;
  final teamScores = [
    for (final game in games) game.summary.homeScore,
    for (final game in games) game.summary.awayScore,
  ];
  final gameTotals = [
    for (final game in games) game.summary.homeScore + game.summary.awayScore,
  ];
  final humanFixture = state.schedule!
      .fixturesForRound(1)
      .firstWhere(
        (fixture) =>
            fixture.homeTeamId == humanTeamId ||
            fixture.awayTeamId == humanTeamId,
      );
  final humanResult = state.gameResults[humanFixture.id]!;
  final humanAtHome = humanFixture.homeTeamId == humanTeamId;
  final humanScore = humanAtHome
      ? humanResult.summary.homeScore
      : humanResult.summary.awayScore;
  final opponentScore = humanAtHome
      ? humanResult.summary.awayScore
      : humanResult.summary.homeScore;
  final opponentId = humanAtHome
      ? humanFixture.awayTeamId
      : humanFixture.homeTeamId;
  final humanLine = humanResult.summary.playerLines.values.firstWhere(
    (line) => line.teamId == humanTeamId.value,
  );
  final standings = state.standings.table.values;
  final leagueWins = standings.fold(0, (sum, team) => sum + team.wins);
  final leagueLosses = standings.fold(0, (sum, team) => sum + team.losses);
  debugPrint(
    'T03 seed=$seed games=${games.length} remaining=${state.remainingGames} '
    'leagueW-L=$leagueWins-$leagueLosses '
    'teamScoreRange=${teamScores.reduce((a, b) => a < b ? a : b)}-'
    '${teamScores.reduce((a, b) => a > b ? a : b)} '
    'meanTeamScore=${(teamScores.fold<int>(0, (sum, score) => sum + score) / teamScores.length).toStringAsFixed(1)} '
    'gameTotalRange=${gameTotals.reduce((a, b) => a < b ? a : b)}-'
    '${gameTotals.reduce((a, b) => a > b ? a : b)} '
    'FG%=${percentage(total((line) => line.fgm), total((line) => line.fga)).toStringAsFixed(1)} '
    '3P%=${percentage(total((line) => line.threePm), total((line) => line.threePa)).toStringAsFixed(1)} '
    'FT%=${percentage(total((line) => line.ftm), total((line) => line.fta)).toStringAsFixed(1)} '
    'REB=${total((line) => line.rebounds)} TO=${total((line) => line.turnovers)} '
    'PF=${total((line) => line.personalFouls)} '
    'minutes=${total((line) => line.secondsPlayed) ~/ 60} '
    'OT=${games.where((game) => game.periodsPlayed > 4).length} '
    'homeWins=${games.where((game) => game.summary.winnerTeamId == game.homeTeamId).length} '
    'roundTransactionMs=$roundTransactionMilliseconds engineMs=$engineMilliseconds',
  );
  debugPrint(
    'T03 human=${humanTeamId.value} opponent=${opponentId.value} '
    'site=${humanAtHome ? 'home' : 'away'} score=$humanScore-$opponentScore '
    'boxSample=${humanLine.playerId}:${humanLine.points}PTS/'
    '${humanLine.rebounds}REB/${humanLine.assists}AST '
    'firstFingerprint=${games.first.inputFingerprint}',
  );
}

Future<void> _runFullSeasonReliability(
  WidgetTester tester,
  GmCareer startingCareer,
) async {
  final startState = startingCareer.regularSeasonState!;
  final schedule = startState.schedule!;
  final rounds = {1, 10, 25, 40, 41, 60, 80, 81, 82};
  final requiredCheckpoints = {1, 10, 25, 41, 60, 81, 82};
  final referenceStates = <int, GmCareer>{0: startingCareer};
  final referenceRoundMilliseconds = <int, int>{};
  var reference = startingCareer;
  for (var round = 1; round <= 82; round++) {
    final watch = Stopwatch()..start();
    reference = const RegularSeasonRoundService().simulateNextRound(
      reference,
      expectedRoundNumber: round,
    );
    watch.stop();
    referenceRoundMilliseconds[round] = watch.elapsedMilliseconds;
    if (rounds.contains(round)) {
      referenceStates[round] = reference;
      debugPrint(
        'T04 REF games=${reference.regularSeasonState!.completedGames} '
        'round=$round simulationMs=${watch.elapsedMilliseconds}',
      );
    }
  }

  final storageDirectory = io.Directory(
    '${io.Directory.current.path}${io.Platform.pathSeparator}.dart_tool',
  );
  final fileStorage = FileGmCareerStorage(directoryPath: storageDirectory.path);
  final storageSlot = 't04-${startingCareer.generationSeed}';
  final checkpointStates = <int, GmCareer>{0: startingCareer};
  var checkpointed = startingCareer;
  Future<void> checkpoint(int round) async {
    final state = checkpointed.regularSeasonState!;
    final progress = state.completedGames;
    debugPrint('T04 CHECKPOINT start games=$progress round=$round');
    final validationWatch = Stopwatch()..start();
    checkpointed.validate();
    validationWatch.stop();
    debugPrint(
      'T04 CHECKPOINT stage=validation games=$progress '
      'ms=${validationWatch.elapsedMilliseconds}',
    );

    final encodeWatch = Stopwatch()..start();
    final encoded = GmCareerCodec.encode(checkpointed);
    encodeWatch.stop();
    final bytes = utf8.encode(encoded).length;
    debugPrint(
      'T04 CHECKPOINT stage=serialize games=$progress '
      'ms=${encodeWatch.elapsedMilliseconds}',
    );

    final writeWatch = Stopwatch()..start();
    await tester.runAsync(() => fileStorage.write(encoded, slot: storageSlot));
    writeWatch.stop();
    debugPrint(
      'T04 CHECKPOINT stage=promote games=$progress '
      'ms=${writeWatch.elapsedMilliseconds}',
    );

    final readWatch = Stopwatch()..start();
    final saved = await tester.runAsync(
      () => fileStorage.read(slot: storageSlot),
    );
    readWatch.stop();
    expect(saved, encoded);
    debugPrint(
      'T04 CHECKPOINT stage=read games=$progress '
      'ms=${readWatch.elapsedMilliseconds}',
    );

    final decodeWatch = Stopwatch()..start();
    checkpointed = GmCareerCodec.decode(saved!);
    decodeWatch.stop();
    checkpointStates[round] = checkpointed;
    debugPrint(
      'T04 CHECKPOINT stage=decode games=$progress '
      'ms=${decodeWatch.elapsedMilliseconds}',
    );

    final queryWatch = Stopwatch()..start();
    expect(checkpointed.regularSeasonState!.standings.ranked, hasLength(30));
    queryWatch.stop();
    final scheduleWatch = Stopwatch()..start();
    expect(
      checkpointed.regularSeasonState!.schedule!.fixturesForTeam(
        checkpointed.userFranchiseId,
      ),
      hasLength(82),
    );
    scheduleWatch.stop();
    final simulationRound = round == 0 ? 1 : round + 1;
    debugPrint(
      'T04 PERF games=$progress round=$round '
      'roundSimulationMs=${referenceRoundMilliseconds[simulationRound] ?? 'unavailable'} '
      'validationMs=${validationWatch.elapsedMilliseconds} '
      'serializeMs=${encodeWatch.elapsedMilliseconds} '
      'decodeMs=${decodeWatch.elapsedMilliseconds} '
      'savePromotionMs=${writeWatch.elapsedMilliseconds} '
      'saveReadMs=${readWatch.elapsedMilliseconds} '
      'standingsQueryMs=${queryWatch.elapsedMilliseconds} '
      'scheduleQueryMs=${scheduleWatch.elapsedMilliseconds} '
      'encodedBytes=$bytes currentRssBytes=${io.ProcessInfo.currentRss}',
    );
  }

  await checkpoint(0);
  for (var round = 1; round <= 82; round++) {
    final watch = Stopwatch()..start();
    checkpointed = const RegularSeasonRoundService().simulateNextRound(
      checkpointed,
      expectedRoundNumber: round,
    );
    watch.stop();
    if (round == 40 || round == 80) {
      checkpointStates[round] = checkpointed;
    }
    if (requiredCheckpoints.contains(round)) {
      await checkpoint(round);
    }
  }

  final expectedSave = GmCareerCodec.encode(reference);
  expect(GmCareerCodec.encode(checkpointed), expectedSave);
  expect(checkpointStates.keys, containsAll({0, 1, 10, 25, 41, 60, 81, 82}));
  expect(
    referenceStates.keys,
    containsAll({0, 1, 10, 25, 40, 41, 60, 80, 81, 82}),
  );
  expect(checkpointed.currentYear, startingCareer.currentYear);
  expect(
    jsonEncode(checkpointed.league.toJson()),
    jsonEncode(startingCareer.league.toJson()),
  );
  expect(
    jsonEncode(checkpointed.finances.toJson()),
    jsonEncode(startingCareer.finances.toJson()),
  );

  final finalState = checkpointed.regularSeasonState!;
  expect(finalState.completedRounds, 82);
  expect(finalState.completedGames, 1230);
  expect(finalState.remainingGames, 0);
  expect(finalState.nextUnfinishedRoundNumber, isNull);
  expect(finalState.gameResults, hasLength(1230));
  expect(_fixtureIdentity(finalState.schedule!), _fixtureIdentity(schedule));
  expect(
    finalState.standings.table.values.fold(0, (sum, row) => sum + row.wins),
    1230,
  );
  expect(
    finalState.standings.table.values.fold(0, (sum, row) => sum + row.losses),
    1230,
  );
  for (final team in startingCareer.league.teams) {
    expect(finalState.gamesPlayedForTeam(team.id), 82);
  }
  expect(
    () => const RegularSeasonRoundService().simulateNextRound(
      checkpointed,
      expectedRoundNumber: 83,
    ),
    throwsStateError,
  );

  await _verifyFullSeasonRecovery(
    tester,
    before: referenceStates[0]!,
    expected: referenceStates[1]!,
    round: 1,
    failBeforePromotion: true,
  );
  await _verifyFullSeasonRecovery(
    tester,
    before: referenceStates[40]!,
    expected: referenceStates[41]!,
    round: 41,
  );
  await _verifyFullSeasonRecovery(
    tester,
    before: referenceStates[80]!,
    expected: referenceStates[81]!,
    round: 81,
  );

  _reportFullSeasonQuality(checkpointed);
  final humanFixture = schedule
      .fixturesForTeam(startingCareer.userFranchiseId)
      .first;
  final humanResult = finalState.gameResults[humanFixture.id]!;
  final humanWins =
      finalState.standings.table[startingCareer.userFranchiseId.value]!.wins;
  final humanLosses =
      finalState.standings.table[startingCareer.userFranchiseId.value]!.losses;
  final sampleLine = humanResult.summary.playerLines.values.first;
  debugPrint(
    'T04 COMPLETE seed=${startingCareer.generationSeed} '
    'rounds=${finalState.completedRounds} games=${finalState.completedGames} '
    'remaining=${finalState.remainingGames} '
    'human=${humanFixture.homeTeamId == startingCareer.userFranchiseId ? 'home' : 'away'} '
    'score=${humanResult.summary.homeScore}-${humanResult.summary.awayScore} '
    'record=$humanWins-$humanLosses '
    'boxSample=${sampleLine.playerId}:${sampleLine.points}PTS '
    'startScheduleFingerprint=${schedule.fingerprint} '
    'completedScheduleFingerprint=${finalState.schedule!.fingerprint} '
    'fixtureIdentity=${schedule.rounds.first.fixtures.first.id}..'
    '${schedule.rounds.last.fixtures.last.id} '
    'year=${checkpointed.currentYear}',
  );

  await _verifyFullSeasonScreens(
    tester,
    early: checkpointStates[1]!,
    middle: checkpointStates[41]!,
    complete: checkpointed,
    humanFixtureId: humanFixture.id,
  );
  final savePath = fileStorage.resolvePath(storageSlot);
  await tester.runAsync(() async {
    for (final suffix in ['', '.tmp', '.bak']) {
      final file = io.File('$savePath$suffix');
      if (await file.exists()) await file.delete();
    }
  });
}

Future<void> _verifyFullSeasonRecovery(
  WidgetTester tester, {
  required GmCareer before,
  required GmCareer expected,
  required int round,
  bool failBeforePromotion = false,
}) async {
  final beforeSave = GmCareerCodec.encode(before);
  final delegate = InMemoryGmCareerStorage({'default': beforeSave});
  final storage = _CommitThenFailCareerStorage(delegate)
    ..failBeforePromotionNextWrite = failBeforePromotion
    ..failNextWrite = !failBeforePromotion;
  final controller = GmCareerController(storage: storage);
  await controller.loadCareer();
  await expectLater(
    _pumpCommand(
      tester,
      controller.simulateNextRegularSeasonRound(
        expectedRoundNumber: round,
        confirmed: true,
      ),
    ),
    throwsA(isA<GmCareerStorageException>()),
  );
  expect(controller.draftRecoveryRequired, isTrue);
  expect(GmCareerCodec.encode(controller.career!), beforeSave);
  final persisted = GmCareerCodec.decode((await delegate.read())!);
  expect(
    GmCareerCodec.encode(persisted),
    failBeforePromotion ? beforeSave : GmCareerCodec.encode(expected),
  );
  await controller.loadCareer();
  expect(controller.draftRecoveryRequired, isFalse);
  if (failBeforePromotion) {
    await _pumpCommand(
      tester,
      controller.simulateNextRegularSeasonRound(
        expectedRoundNumber: round,
        confirmed: true,
      ),
    );
  }
  expect(
    GmCareerCodec.encode(controller.career!),
    GmCareerCodec.encode(expected),
  );
  expect(controller.career!.regularSeasonState!.completedRounds, round);
  expect(
    controller.career!.regularSeasonState!.gameResults,
    hasLength(round * 15),
  );
  debugPrint(
    'T04 RECOVERY round=$round '
    'failure=${failBeforePromotion ? 'pre-promotion' : 'post-promotion-uncertain'} '
    'reloaded=${controller.career!.regularSeasonState!.completedGames} '
    'next=${controller.career!.regularSeasonState!.nextUnfinishedRoundNumber} '
    'matchesReference=true',
  );
  controller.dispose();
}

Future<void> _verifyFullSeasonScreens(
  WidgetTester tester, {
  required GmCareer early,
  required GmCareer middle,
  required GmCareer complete,
  required String humanFixtureId,
}) async {
  for (final (label, career) in <(String, GmCareer)>[
    ('early', early),
    ('middle', middle),
    ('complete', complete),
  ]) {
    final storage = InMemoryGmCareerStorage({
      'default': GmCareerCodec.encode(career),
    });
    final controller = GmCareerController(storage: storage);
    await controller.loadCareer();
    for (final size in const [Size(360, 640), Size(393, 852)]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(
        MaterialApp(home: RegularSeasonOverviewScreen(controller: controller)),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$label overview $size');
      if (label == 'complete') {
        expect(find.text('Regular Season Complete'), findsOneWidget);
        expect(find.text('Simulate Next Round'), findsNothing);
      }
    }
    controller.dispose();
  }

  final state = complete.regularSeasonState!;
  final fixture = state.schedule!.rounds
      .expand((round) => round.fixtures)
      .firstWhere((game) => game.id == humanFixtureId);
  for (final size in const [Size(360, 640), Size(393, 852)]) {
    tester.view.physicalSize = size;
    await tester.pumpWidget(
      MaterialApp(home: RegularSeasonResultsScreen(career: complete)),
    );
    await tester.pumpAndSettle();
    expect(find.text('League Results'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'completed results $size');
    await tester.pumpWidget(
      MaterialApp(home: RegularSeasonScheduleScreen(career: complete)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Team Schedule'), findsOneWidget);
    expect(find.textContaining('Final '), findsWidgets);

    await tester.pumpWidget(
      MaterialApp(
        home: RegularSeasonBoxScoreScreen(
          career: complete,
          fixtureId: fixture.id,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Box Score'), findsOneWidget);
    expect(find.textContaining('PTS'), findsWidgets);
    expect(tester.takeException(), isNull, reason: 'completed box score $size');

    await tester.pumpWidget(
      MaterialApp(home: RegularSeasonStandingsScreen(career: complete)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Standings'), findsOneWidget);
    expect(find.textContaining('GP 82'), findsWidgets);
    expect(tester.takeException(), isNull, reason: 'completed standings $size');
  }
}

String _fixtureIdentity(RegularSeasonSchedule schedule) => jsonEncode([
  schedule.seasonId,
  schedule.seasonYear,
  schedule.scheduleSeed,
  for (final round in schedule.rounds)
    [
      round.roundNumber,
      for (final fixture in round.fixtures)
        [
          fixture.id,
          fixture.seasonId,
          fixture.seasonYear,
          fixture.roundNumber,
          fixture.fixturePosition,
          fixture.homeTeamId.value,
          fixture.awayTeamId.value,
          fixture.gameSeed,
        ],
    ],
]);
void _reportFullSeasonQuality(GmCareer career) {
  final state = career.regularSeasonState!;
  final games = state.gameResults.values.toList()
    ..sort((a, b) => a.fixtureId.compareTo(b.fixtureId));
  final teamPoints = <double>[];
  final combinedPoints = <double>[];
  final fieldGoalPercentages = <double>[];
  final threePointPercentages = <double>[];
  final freeThrowPercentages = <double>[];
  final rebounds = <double>[];
  final assists = <double>[];
  final turnovers = <double>[];
  final fouls = <double>[];
  final minutes = <double>[];
  final scoringLines = <SeasonPlayerGameLine>[];
  var homeWins = 0;

  int total(
    Iterable<SeasonPlayerGameLine> lines,
    int Function(SeasonPlayerGameLine) select,
  ) => lines.fold(0, (sum, line) => sum + select(line));

  for (final game in games) {
    final summary = game.summary;
    teamPoints
      ..add(summary.homeScore.toDouble())
      ..add(summary.awayScore.toDouble());
    combinedPoints.add((summary.homeScore + summary.awayScore).toDouble());
    if (summary.winnerTeamId == game.homeTeamId) homeWins++;
    for (final teamId in [game.homeTeamId.value, game.awayTeamId.value]) {
      final lines = summary.playerLines.values
          .where((line) => line.teamId == teamId)
          .toList(growable: false);
      final fgm = total(lines, (line) => line.fgm);
      final fga = total(lines, (line) => line.fga);
      final threePm = total(lines, (line) => line.threePm);
      final threePa = total(lines, (line) => line.threePa);
      final ftm = total(lines, (line) => line.ftm);
      final fta = total(lines, (line) => line.fta);
      if (fga > 0) fieldGoalPercentages.add(100 * fgm / fga);
      if (threePa > 0) threePointPercentages.add(100 * threePm / threePa);
      if (fta > 0) freeThrowPercentages.add(100 * ftm / fta);
      rebounds.add(total(lines, (line) => line.rebounds).toDouble());
      assists.add(total(lines, (line) => line.assists).toDouble());
      turnovers.add(total(lines, (line) => line.turnovers).toDouble());
      fouls.add(total(lines, (line) => line.personalFouls).toDouble());
    }
    for (final line in summary.playerLines.values) {
      minutes.add(line.secondsPlayed / 60);
      scoringLines.add(line);
    }
  }

  void report(String label, List<double> values) {
    values.sort();
    final mean = values.reduce((a, b) => a + b) / values.length;
    final variance =
        values.fold(
          0.0,
          (sum, value) => sum + math.pow(value - mean, 2).toDouble(),
        ) /
        values.length;
    double percentile(double p) => values[((values.length - 1) * p).round()];
    debugPrint(
      'T04 DIST $label n=${values.length} '
      'mean=${mean.toStringAsFixed(2)} '
      'median=${percentile(0.5).toStringAsFixed(2)} '
      'min=${values.first.toStringAsFixed(2)} '
      'max=${values.last.toStringAsFixed(2)} '
      'sd=${math.sqrt(variance).toStringAsFixed(2)} '
      'p10=${percentile(0.1).toStringAsFixed(2)} '
      'p25=${percentile(0.25).toStringAsFixed(2)} '
      'p75=${percentile(0.75).toStringAsFixed(2)} '
      'p90=${percentile(0.9).toStringAsFixed(2)}',
    );
  }

  report('teamPoints', teamPoints);
  report('combinedPoints', combinedPoints);
  report('teamGameFGPercent', fieldGoalPercentages);
  report('teamGame3PPercent', threePointPercentages);
  report('teamGameFTPercent', freeThrowPercentages);
  report('teamGameRebounds', rebounds);
  report('teamGameAssists', assists);
  report('teamGameTurnovers', turnovers);
  report('teamGamePersonalFouls', fouls);
  report('playerGameMinutes', minutes);
  final overtimeGames = games.where((game) => game.periodsPlayed > 4).length;
  final maxScorer = scoringLines.reduce((a, b) => a.points >= b.points ? a : b);
  debugPrint(
    'T04 QUALITY games=${games.length} homeWinPercent='
    '${(100 * homeWins / games.length).toStringAsFixed(2)} '
    'overtime=$overtimeGames/${games.length} '
    'playerGamesOver40=${scoringLines.where((line) => line.points > 40).length} '
    'playerGamesOver50=${scoringLines.where((line) => line.points > 50).length} '
    'maxScoringLine=${maxScorer.playerId}/${maxScorer.teamId}:'
    '${maxScorer.points}PTS',
  );

  final teamStrength = [
    for (final team in career.league.teams)
      (
        team: team,
        rating:
            team.players.fold<int>(
              0,
              (sum, player) => sum + player.attributes.overallRating,
            ) /
            team.players.length,
        wins: state.standings.table[team.id.value]!.wins,
      ),
  ]..sort((a, b) => a.rating.compareTo(b.rating));
  final ratingMean =
      teamStrength.fold<double>(0, (sum, team) => sum + team.rating) /
      teamStrength.length;
  final winMean =
      teamStrength.fold<int>(0, (sum, team) => sum + team.wins) /
      teamStrength.length;
  final covariance = teamStrength.fold<double>(
    0,
    (sum, team) => sum + (team.rating - ratingMean) * (team.wins - winMean),
  );
  final ratingVariance = teamStrength.fold<double>(
    0,
    (sum, team) => sum + math.pow(team.rating - ratingMean, 2).toDouble(),
  );
  final winVariance = teamStrength.fold<double>(
    0,
    (sum, team) => sum + math.pow(team.wins - winMean, 2).toDouble(),
  );
  final topQuartile = teamStrength.skip(teamStrength.length - 7).toList();
  final bottomQuartile = teamStrength.take(7).toList();
  debugPrint(
    'T04 STRENGTH publicOVRWinCorrelation='
    '${(covariance / math.sqrt(ratingVariance * winVariance)).toStringAsFixed(3)} '
    'top7MeanWins=${(topQuartile.fold<int>(0, (sum, team) => sum + team.wins) / 7).toStringAsFixed(2)} '
    'bottom7MeanWins=${(bottomQuartile.fold<int>(0, (sum, team) => sum + team.wins) / 7).toStringAsFixed(2)}',
  );
}

void _reportStartingSituationSeasons(
  Map<FranchiseSituation, GmCareer> startingCareers,
) {
  expect(startingCareers.keys, containsAll(FranchiseSituation.values));
  const roundService = RegularSeasonRoundService();
  for (final situation in FranchiseSituation.values) {
    final starting = startingCareers[situation]!;
    var career = starting;
    for (var round = 1; round <= 82; round++) {
      career = roundService.simulateNextRound(
        career,
        expectedRoundNumber: round,
      );
    }
    career.validate();
    final state = career.regularSeasonState!;
    final userRecord = state.standings.table[career.userFranchiseId.value]!;
    expect(state.completedRounds, 82);
    expect(state.gameResults, hasLength(1230));
    expect(career.currentYear, starting.currentYear);
    debugPrint(
      'T04 START-SITUATION ${situation.jsonValue} '
      'seed=${state.scheduleSeed} rounds=${state.completedRounds} '
      'games=${state.gameResults.length} '
      'userRecord=${userRecord.wins}-${userRecord.losses} '
      'year=${career.currentYear}',
    );
  }
}

Future<T> _pumpCommand<T>(WidgetTester tester, Future<T> command) async {
  var completed = false;
  T? value;
  Object? failure;
  StackTrace? failureStack;
  command.then(
    (result) {
      value = result;
      completed = true;
    },
    onError: (Object error, StackTrace stack) {
      failure = error;
      failureStack = stack;
      completed = true;
    },
  );
  for (var attempt = 0; attempt < 600 && !completed; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
  }
  expect(
    completed,
    isTrue,
    reason: 'Career command did not complete within 30 seconds',
  );
  if (failure != null) {
    Error.throwWithStackTrace(failure!, failureStack!);
  }
  return value as T;
}

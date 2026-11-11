import 'dart:async';
import 'dart:convert';

import 'package:basketball_manager/app.dart';
import 'package:basketball_manager/features/career/career_controller.dart';
import 'package:basketball_manager/features/career/career_storage.dart';
import 'package:basketball_manager/features/career/draft_board_screen.dart';
import 'package:basketball_manager/features/career/offseason_overview_screen.dart';
import 'package:basketball_manager/features/season/season_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simulation_core/simulation_core.dart';

const _seed = 20261028;
const _smallViewport = Size(360, 640);
const _largeViewport = Size(393, 852);

void main() {
  final careers = <FranchiseSituation, GmCareer>{};

  setUpAll(() {
    for (final situation in FranchiseSituation.values) {
      careers[situation] = GmCareer.fromSetupResult(
        const CareerSetupService().generate(
          CareerSetupRequest(
            selectedTeamId: const TeamId('team-1'),
            selectedSituation: situation,
            seed: _seed,
          ),
        ),
        id: 'interactive-draft-${situation.name}',
      );
    }
  });

  group('M008-T06B interactive draft', () {
    for (final situation in FranchiseSituation.values) {
      testWidgets(
        '${situation.name}: cancel start, stop at both owned picks, explicitly complete 60, and restart without replay',
        (tester) async {
          _viewport(
            tester,
            situation.index.isEven ? _smallViewport : _largeViewport,
          );
          final original = careers[situation]!;
          final fixture = await _Fixture.create(original);
          var controller = fixture.controller;
          final storage = fixture.storage;
          final firstPick = situation.userOpeningDraftPick;
          final secondPick = firstPick + 30;
          final originalRaw = storage.data;

          await _mountOverview(tester, controller);
          await _openBoard(tester);
          expect(
            identical(
              tester
                  .widget<GmDraftBoardScreen>(find.byType(GmDraftBoardScreen))
                  .controller,
              controller,
            ),
            isTrue,
          );
          await _tapKey(tester, 'draft-start-button');
          final startText = _dialogText(tester);
          for (final value in [
            original.userTeam.name,
            '$firstPick',
            '$secondPick',
            '90',
            '60',
          ]) {
            expect(startText, contains(value));
          }
          await _tapKey(tester, 'cancel-start-draft');
          expect(storage.attempts, 0);
          expect(storage.data, originalRaw);
          expect(controller.career!.draftExecutionState.isNotStarted, isTrue);

          await _startDraft(tester);
          _expectHumanTurn(controller, firstPick);
          expect(storage.selectionCounts, List.generate(firstPick, (i) => i));
          expect(
            find.byKey(const ValueKey('draft-start-button')),
            findsNothing,
          );
          expect(
            _textAt(tester, 'draft-progress'),
            contains('${firstPick - 1}'),
          );
          final currentText = _textAt(tester, 'draft-current-pick');
          expect(currentText, contains('$firstPick'));
          expect(currentText, contains(original.userTeam.name));
          expect(currentText, contains(original.userTeam.abbreviation));
          expect(tester.takeException(), isNull);

          final firstChoice = controller.career!.draftExecutionState
              .availableProspects(controller.career!.draftClass)
              .last;
          final beforeCancel = storage.data;
          final attemptsBeforeCancel = storage.attempts;
          await _openSelectionConfirmation(tester, firstChoice);
          final confirmation = _dialogText(tester);
          for (final value in [
            firstChoice.fullName,
            '${firstChoice.age}',
            firstChoice.position.shortName,
            '${firstChoice.overallRating}',
            '${firstChoice.projectedRank}',
            firstChoice.estimatedPotentialGrade,
            firstChoice.estimatedPotentialRange,
            '1',
            '$firstPick',
            original.userTeam.name,
          ]) {
            expect(confirmation, contains(value));
          }
          await _tapKey(tester, 'cancel-draft-player');
          expect(storage.attempts, attemptsBeforeCancel);
          expect(storage.data, beforeCancel);
          _expectHumanTurn(controller, firstPick);
          await _tapKey(tester, 'draft-player-button');
          await _tapKey(tester, 'confirm-draft-player');

          _expectHumanTurn(controller, secondPick);
          expect(storage.selectionCounts, List.generate(secondPick, (i) => i));
          final firstSelection =
              controller.career!.draftExecutionState.selections[firstPick - 1];
          expect(firstSelection.prospectId, firstChoice.id);
          expect(firstSelection.selectingTeamId, original.userFranchiseId);
          expect(firstSelection.round, 1);
          expect(firstSelection.pickInRound, firstPick);
          expect(storage.data, GmCareerCodec.encode(controller.career!));
          await _expectSelectedProspect(tester, firstChoice);

          final midDraftRaw = storage.data;
          final attemptsBeforeRestart = storage.attempts;
          await tester.pumpWidget(const SizedBox.shrink());
          controller = GmCareerController(storage: storage);
          addTearDown(controller.dispose);
          await controller.loadCareer();
          await _mountOverview(tester, controller);
          expect(GmCareerCodec.encode(controller.career!), midDraftRaw);
          expect(storage.attempts, attemptsBeforeRestart);
          await _revealOverviewButton(tester);
          expect(find.text('Resume Draft'), findsWidgets);
          await _tapKey(tester, 'btn-open-draft-board');
          await _tapKey(tester, 'draft-resume-button');
          _expectHumanTurn(controller, secondPick);
          expect(storage.attempts, attemptsBeforeRestart);
          await _expectSelectedProspect(tester, firstChoice);

          final secondChoice = controller.career!.draftExecutionState
              .availableProspects(controller.career!.draftClass)
              .last;
          await _openSelectionConfirmation(tester, secondChoice);
          expect(_dialogText(tester), contains('2'));
          expect(_dialogText(tester), contains('$secondPick'));
          await _tapKey(tester, 'confirm-draft-player');

          final completed = controller.career!;
          final execution = completed.draftExecutionState;
          expect(execution.isCompleted, isTrue);
          expect(execution.currentOverallPick, isNull);
          expect(execution.selections, hasLength(60));
          expect(execution.selectedProspectIds, hasLength(60));
          expect(execution.draftRights, hasLength(60));
          expect(
            execution.undraftedProspects(completed.draftClass),
            hasLength(30),
          );
          final undrafted = execution
              .undraftedProspects(completed.draftClass)
              .last;
          await _openProspect(tester, undrafted);
          expect(_sheetText(tester), contains('Undrafted'));
          expect(_sheetText(tester), contains('Available'));
          expect(
            tester
                .widget<ButtonStyleButton>(
                  find.byKey(const ValueKey('draft-player-button')),
                )
                .onPressed,
            isNull,
          );
          await _dismissSheet(tester);
          expect(
            execution.selections[secondPick - 1].prospectId,
            secondChoice.id,
          );
          expect(execution.selections[secondPick - 1].round, 2);
          expect(execution.selections[secondPick - 1].pickInRound, firstPick);
          expect(storage.selectionCounts, List.generate(61, (i) => i));
          final ownedRights = execution.draftRights.values
              .where((right) => right.owningTeamId == original.userFranchiseId)
              .toList();
          expect(ownedRights.map((right) => right.prospectId), [
            firstChoice.id,
            secondChoice.id,
          ]);
          _expectUnchangedRosters(original, storage.commits);
          expect(storage.clears, 0);
          await _expectResults(tester, firstChoice, secondChoice);
          await _expectOrderHistory(
            tester,
            completed,
            everyPick: situation == FranchiseSituation.tanking,
          );
          expect(tester.takeException(), isNull);

          final completedRaw = storage.data;
          final completedAttempts = storage.attempts;
          await tester.pumpWidget(const SizedBox.shrink());
          final restarted = GmCareerController(storage: storage);
          addTearDown(restarted.dispose);
          await restarted.loadCareer();
          await _mountOverview(tester, restarted);
          await _revealOverviewButton(tester);
          expect(find.text('View Draft Results'), findsWidgets);
          await _tapKey(tester, 'btn-open-draft-board');
          await _expectResults(tester, firstChoice, secondChoice);
          expect(GmCareerCodec.encode(restarted.career!), completedRaw);
          expect(storage.data, completedRaw);
          expect(storage.attempts, completedAttempts);
          expect(
            find.byKey(const ValueKey('draft-start-button')),
            findsNothing,
          );
          expect(
            find.byKey(const ValueKey('draft-resume-button')),
            findsNothing,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets(
      'AI commits remain live while storage is gated, including exit and re-entry',
      (tester) async {
        _viewport(tester, _smallViewport);
        final original = careers[FranchiseSituation.playIn]!;
        final storage = _ObservedStorage(original);
        final seasonStorage = InMemorySeasonStorage();
        await tester.pumpWidget(
          BasketballManagerApp(
            league: original.league,
            careerStorage: storage,
            storage: seasonStorage,
            seasonMode: true,
          ),
        );
        await tester.pumpAndSettle();
        const sentinel = '{"m007-sentinel":"unchanged-during-draft"}';
        await seasonStorage.write(sentinel);
        final controller = tester
            .widget<GmOffseasonOverviewScreen>(
              find.byType(GmOffseasonOverviewScreen),
            )
            .controller;
        await _openBoard(tester);
        final gate = storage.gateAt(3);
        await _tapKey(tester, 'draft-start-button');
        await tester.tap(find.byKey(const ValueKey('confirm-start-draft')));
        await tester.pump();
        final pending = await gate.entered.future;
        await tester.pump();

        expect(pending.draftExecutionState.completedSelectionsCount, 3);
        expect(controller.isLoading, isTrue);
        expect(controller.career!.draftExecutionState.selections, hasLength(2));
        expect(storage.saved.draftExecutionState.selections, hasLength(2));
        expect(find.byType(GmDraftBoardScreen), findsOneWidget);
        expect(_textAt(tester, 'draft-status'), contains('AI Drafting'));
        expect(_textAt(tester, 'draft-progress'), contains('2'));
        final latest = controller.career!.draftExecutionState.selections.last;
        final prospect = original.draftClass.byId(latest.prospectId)!;
        final team = original.league.teams.firstWhere(
          (team) => team.id == latest.selectingTeamId,
        );
        final latestText = _textAt(tester, 'draft-latest-selection');
        for (final value in [
          team.name,
          '${latest.overallPick}',
          prospect.fullName,
          prospect.position.shortName,
          '${prospect.overallRating}',
        ]) {
          expect(latestText, contains(value));
        }

        // Pump bounded frames only while the storage gate deliberately stays shut.
        await tester.binding.handlePopRoute();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byType(GmOffseasonOverviewScreen), findsOneWidget);
        expect(controller.isLoading, isTrue);
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('btn-open-draft-board')),
          160,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.byKey(const ValueKey('btn-open-draft-board')));
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byType(GmDraftBoardScreen), findsOneWidget);
        expect(controller.career!.draftExecutionState.selections, hasLength(2));
        expect(storage.attempts, 4);
        expect(tester.takeException(), isNull);

        gate.release.complete();
        await tester.pumpAndSettle();
        _expectHumanTurn(controller, 12);
        expect(storage.selectionCounts, List.generate(12, (i) => i));
        expect(await seasonStorage.read(), sentinel);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'duplicate start and human confirmation taps submit once without optimistic selection',
      (tester) async {
        _viewport(tester, _smallViewport);
        final fixture = await _Fixture.create(
          careers[FranchiseSituation.tanking]!,
        );
        final controller = fixture.controller;
        final storage = fixture.storage;
        await _mountBoard(tester, controller);
        final startGate = storage.gateAt(0);
        await _tapKey(tester, 'draft-start-button');
        final startTarget = tester.getCenter(
          find.byKey(const ValueKey('confirm-start-draft')),
        );
        await tester.tapAt(startTarget);
        await tester.tapAt(startTarget);
        await tester.pump();
        await startGate.entered.future;
        expect(controller.career!.draftExecutionState.isNotStarted, isTrue);
        expect(storage.attempts, 1);
        startGate.release.complete();
        await tester.pumpAndSettle();
        _expectHumanTurn(controller, 1);
        expect(storage.selectionCounts, [0]);

        final choice = controller.career!.draftClass.prospects.last;
        await _openSelectionConfirmation(tester, choice);
        final gate = storage.gateAt(1);
        final before = storage.data;
        final humanTarget = tester.getCenter(
          find.byKey(const ValueKey('confirm-draft-player')),
        );
        await tester.tapAt(humanTarget);
        await tester.tapAt(humanTarget);
        await tester.pump();
        await gate.entered.future;
        await tester.pump();
        expect(controller.isLoading, isTrue);
        expect(controller.career!.draftExecutionState.selections, isEmpty);
        expect(
          controller.career!.draftExecutionState.isProspectSelected(choice.id),
          isFalse,
        );
        expect(storage.data, before);
        expect(storage.attempts, 2);
        expect(tester.takeException(), isNull);
        gate.release.complete();
        await tester.pumpAndSettle();
        _expectHumanTurn(controller, 31);
        expect(storage.selectionCounts, List.generate(31, (i) => i));
        expect(
          controller.career!.draftExecutionState.selections.first.prospectId,
          choice.id,
        );
        expect(controller.errorMessage, isNull);
        await _expectSelectedProspect(tester, choice);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'an old confirmation cannot consume the next human turn after career changes',
      (tester) async {
        _viewport(tester, _largeViewport);
        final fixture = await _Fixture.create(
          careers[FranchiseSituation.tanking]!,
        );
        final controller = fixture.controller;
        await _mountBoard(tester, controller);
        await _startDraft(tester);
        final otherChoice = controller.career!.draftClass.rankedFirst;
        const service = DraftExecutionService();
        final afterExternalSelection = service.advanceUntilHumanOrComplete(
          service.makeHumanSelection(
            career: controller.career!,
            prospectId: otherChoice.id,
          ),
        );
        final staleChoice = afterExternalSelection.draftExecutionState
            .availableProspects(afterExternalSelection.draftClass)
            .last;
        await _openSelectionConfirmation(tester, staleChoice);

        // A second live owner changes the career while this confirmation stays open.
        await controller.makeHumanSelection(prospectId: otherChoice.id);
        await tester.pumpAndSettle();
        _expectHumanTurn(controller, 31);
        final committed = fixture.storage.data;
        final attempts = fixture.storage.attempts;
        final staleConfirmation = find.byKey(
          const ValueKey('confirm-draft-player'),
        );
        if (staleConfirmation.evaluate().isNotEmpty &&
            tester.widget<ButtonStyleButton>(staleConfirmation).onPressed !=
                null) {
          await tester.tap(staleConfirmation);
          await tester.pumpAndSettle();
        }
        expect(fixture.storage.attempts, attempts);
        expect(fixture.storage.data, committed);
        _expectHumanTurn(controller, 31);
        expect(
          controller.career!.draftExecutionState.isProspectSelected(
            staleChoice.id,
          ),
          isFalse,
        );
        expect(tester.takeException(), isNull);
      },
    );

    for (final failAfterCommit in [false, true]) {
      testWidgets(
        'save failure ${failAfterCommit ? 'after' : 'before'} commitment requires explicit reload and resume',
        (tester) async {
          _viewport(tester, _smallViewport);
          final original = careers[FranchiseSituation.tanking]!;
          final fixture = await _Fixture.create(original);
          final controller = fixture.controller;
          final storage = fixture.storage;
          await _mountBoard(tester, controller);
          await _startDraft(tester);
          final choice = controller.career!.draftClass.prospects.last;
          storage.failAtSelectionCount = 3;
          storage.failAfterCommit = failAfterCommit;
          await _openSelectionConfirmation(tester, choice);
          await _tapKey(tester, 'confirm-draft-player');
          await _dismissSheet(tester);

          expect(controller.draftRecoveryRequired, isTrue);
          expect(controller.isLoading, isFalse);
          expect(
            controller.career!.draftExecutionState.selections,
            hasLength(2),
          );
          expect(
            storage.saved.draftExecutionState.selections,
            hasLength(failAfterCommit ? 3 : 2),
          );
          expect(
            controller.career!.draftExecutionState.selections.first.prospectId,
            choice.id,
          );
          expect(
            find.textContaining('Injected draft write failure'),
            findsWidgets,
          );
          expect(
            find.byKey(const ValueKey('draft-reload-button')),
            findsOneWidget,
          );
          final attempts = storage.attempts;
          final committed = storage.data;
          await tester.pump(const Duration(seconds: 1));
          expect(storage.attempts, attempts);
          expect(find.text('Retry'), findsNothing);
          final resume = find.byKey(const ValueKey('draft-resume-button'));
          if (resume.evaluate().isNotEmpty) {
            expect(tester.widget<ButtonStyleButton>(resume).onPressed, isNull);
          }
          await _expectSelectedProspect(tester, choice);
          expect(storage.attempts, attempts);

          storage.failReads = true;
          await _tapKey(tester, 'draft-reload-button');
          expect(controller.draftRecoveryRequired, isTrue);
          expect(
            find.textContaining('Injected draft read failure'),
            findsWidgets,
          );
          expect(storage.data, committed);
          expect(storage.attempts, attempts);
          storage.failReads = false;
          final history = storage.saved.draftExecutionState.selections
              .map((selection) => selection.toJson())
              .toList();
          await _tapKey(tester, 'draft-reload-button');
          expect(controller.draftRecoveryRequired, isFalse);
          expect(controller.errorMessage, isNull);
          expect(GmCareerCodec.encode(controller.career!), committed);
          expect(storage.attempts, attempts);
          await _tapKey(tester, 'draft-resume-button');
          _expectHumanTurn(controller, 31);
          expect(
            controller.career!.draftExecutionState.selections
                .take(history.length)
                .map((selection) => selection.toJson())
                .toList(),
            history,
          );
          expect(storage.selectionCounts, List.generate(31, (i) => i));
          expect(
            controller.career!.draftExecutionState.selections.where(
              (selection) => selection.prospectId == choice.id,
            ),
            hasLength(1),
          );
          expect(storage.clears, 0);
          _expectUnchangedRosters(original, storage.commits);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets(
      'a rejected human save blocks the same choice until explicit reconciliation',
      (tester) async {
        _viewport(tester, _smallViewport);
        final fixture = await _Fixture.create(
          careers[FranchiseSituation.tanking]!,
        );
        final controller = fixture.controller;
        final storage = fixture.storage;
        await _mountBoard(tester, controller);
        await _startDraft(tester);
        final choice = controller.career!.draftClass.prospects.last;
        final before = storage.data;
        storage.failAtSelectionCount = 1;
        await _openSelectionConfirmation(tester, choice);
        await _tapKey(tester, 'confirm-draft-player');
        await _dismissSheet(tester);
        _expectHumanTurn(controller, 1);
        expect(controller.draftRecoveryRequired, isTrue);
        expect(storage.data, before);
        expect(storage.attempts, 2);
        await _openProspect(tester, choice);
        expect(_sheetText(tester), contains('Available'));
        expect(
          tester
              .widget<ButtonStyleButton>(
                find.byKey(const ValueKey('draft-player-button')),
              )
              .onPressed,
          isNull,
        );
        await tester.pump(const Duration(seconds: 1));
        expect(storage.attempts, 2);
        await _dismissSheet(tester);
        await _tapKey(tester, 'draft-reload-button');
        expect(controller.draftRecoveryRequired, isFalse);
        expect(storage.attempts, 2);
        _expectHumanTurn(controller, 1);
        await _openSelectionConfirmation(tester, choice);
        await _tapKey(tester, 'confirm-draft-player');
        _expectHumanTurn(controller, 31);
        expect(
          controller.career!.draftExecutionState.selections.first.prospectId,
          choice.id,
        );
        expect(storage.selectionCounts, List.generate(31, (i) => i));
        expect(tester.takeException(), isNull);
      },
    );

    for (final size in [_smallViewport, _largeViewport]) {
      testWidgets(
        'public scouting, all position filters, search and round filters fit $size',
        (tester) async {
          _viewport(tester, size);
          final original = careers[FranchiseSituation.tanking]!;
          final fixture = await _Fixture.create(original);
          await _mountBoard(tester, fixture.controller);
          await _tapText(tester, 'Round 1 (30)');
          expect(_orderCount(tester), 30);
          await _tapText(tester, 'Round 2 (30)');
          expect(_orderCount(tester), 30);
          await tester.scrollUntilVisible(
            find.byKey(const ValueKey('draft-pick-31')),
            160,
            scrollable: find
                .descendant(
                  of: find.byKey(const ValueKey('draft-order-list')),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          expect(find.byKey(const ValueKey('draft-pick-31')), findsOneWidget);
          await _tapText(tester, 'All (60)');
          expect(_orderCount(tester), 60);
          await _tab(tester, 1);
          expect(
            find.textContaining('Showing 90 of 90 Prospects'),
            findsOneWidget,
          );
          for (final position in Position.values) {
            final filter = find.byKey(
              ValueKey('prospect-filter-${position.shortName.toLowerCase()}'),
            );
            await tester.ensureVisible(filter);
            await tester.pumpAndSettle();
            await tester.tap(filter);
            await tester.pumpAndSettle();
            final count = original.draftClass.byPosition(position).length;
            expect(
              find.textContaining('Showing $count of 90 Prospects'),
              findsOneWidget,
            );
            final firstOfPosition = original.draftClass
                .byPosition(position)
                .first;
            await tester.scrollUntilVisible(
              find.byKey(
                ValueKey('prospect-card-${firstOfPosition.projectedRank}'),
              ),
              160,
              scrollable: find
                  .descendant(
                    of: find.byKey(const ValueKey('prospect-list')),
                    matching: find.byType(Scrollable),
                  )
                  .first,
            );
            final cards = tester.widgetList<Card>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is Card &&
                    widget.key is ValueKey<String> &&
                    (widget.key! as ValueKey<String>).value.startsWith(
                      'prospect-card-',
                    ),
              ),
            );
            expect(cards, isNotEmpty);
            for (final card in cards) {
              final rank = int.parse(
                (card.key! as ValueKey<String>).value.split('-').last,
              );
              expect(
                original.draftClass.prospects
                    .firstWhere((prospect) => prospect.projectedRank == rank)
                    .position,
                position,
              );
            }
          }
          await _tapKey(tester, 'prospect-filter-all');
          await tester.enterText(
            find.byKey(const ValueKey('prospect-search-field')),
            'not-a-prospect-xyz',
          );
          await tester.pumpAndSettle();
          expect(find.text('No prospects match your criteria'), findsOneWidget);
          final prospect = original.draftClass.rankedFirst;
          await _openProspect(tester, prospect);
          expect(
            tester
                .widget<ButtonStyleButton>(
                  find.byKey(const ValueKey('draft-player-button')),
                )
                .onPressed,
            isNull,
          );
          final firstPublicText = await _allSheetText(tester);
          expect(firstPublicText, contains('Public Scouting Evaluation'));
          expect(firstPublicText, contains('Observed Abilities'));
          expect(firstPublicText, isNot(contains('True Potential')));
          for (final trajectory in DevelopmentTrajectory.values) {
            expect(firstPublicText, isNot(contains(trajectory.displayName)));
          }
          await _dismissSheet(tester);

          final hiddenChanged = RookieProspect(
            id: prospect.id,
            firstName: prospect.firstName,
            lastName: prospect.lastName,
            position: prospect.position,
            age: prospect.age,
            attributes: prospect.attributes,
            potential: prospect.potential == 100 ? prospect.overallRating : 100,
            trajectory: DevelopmentTrajectory.values.firstWhere(
              (trajectory) => trajectory != prospect.trajectory,
            ),
            projectedRank: prospect.projectedRank,
            estimatedPotentialGrade: prospect.estimatedPotentialGrade,
            estimatedPotentialRange: prospect.estimatedPotentialRange,
          );
          final changedFixture = await _Fixture.create(
            original.copyWith(
              draftClass: RookieDraftClass(
                seasonYear: original.draftClass.seasonYear,
                prospects: [
                  for (final candidate in original.draftClass.prospects)
                    if (candidate.id == prospect.id)
                      hiddenChanged
                    else
                      candidate,
                ],
              ),
            ),
          );
          await tester.pumpWidget(const SizedBox.shrink());
          await _mountBoard(tester, changedFixture.controller);
          await _openProspect(tester, hiddenChanged);
          expect(
            await _allSheetText(tester),
            firstPublicText,
            reason:
                'Changing only hidden fields must not change rendered scouting.',
          );
          expect(tester.takeException(), isNull);
          expect(fixture.storage.attempts, 0);
          expect(changedFixture.storage.attempts, 0);
        },
      );
    }
  });
}

void _viewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Widget _app(Widget home) => MaterialApp(
  theme: ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFB4541E)),
  ),
  home: home,
);

Future<void> _mountBoard(
  WidgetTester tester,
  GmCareerController controller,
) async {
  await tester.pumpWidget(_app(GmDraftBoardScreen(controller: controller)));
  await tester.pumpAndSettle();
}

Future<void> _mountOverview(
  WidgetTester tester,
  GmCareerController controller,
) async {
  await tester.pumpWidget(
    _app(GmOffseasonOverviewScreen(controller: controller)),
  );
  await tester.pumpAndSettle();
}

Future<void> _revealOverviewButton(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.byKey(const ValueKey('btn-open-draft-board')),
    160,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

Future<void> _openBoard(WidgetTester tester) async {
  await _revealOverviewButton(tester);
  await _tapKey(tester, 'btn-open-draft-board');
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  final target = find.byKey(ValueKey(key));
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _tapText(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text));
  await tester.pumpAndSettle();
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

Future<void> _tab(WidgetTester tester, int index) async {
  final tabs = find.descendant(
    of: find.byKey(const ValueKey('draft-board-tab-bar')),
    matching: find.byType(Tab),
  );
  expect(tabs, findsNWidgets(3));
  final label = find
      .descendant(of: tabs.at(index), matching: find.byType(Text))
      .first;
  await tester.ensureVisible(label);
  await tester.pumpAndSettle();
  await tester.tap(label);
  await tester.pumpAndSettle();
}

Future<void> _startDraft(WidgetTester tester) async {
  await _tapKey(tester, 'draft-start-button');
  await _tapKey(tester, 'confirm-start-draft');
}

Future<void> _openProspect(WidgetTester tester, RookieProspect prospect) async {
  await _dismissSheet(tester);
  await _tab(tester, 1);
  final list = find.byKey(const ValueKey('prospect-list'));
  await tester.scrollUntilVisible(
    find.byKey(const ValueKey('prospect-search-field')),
    -240,
    scrollable: find
        .descendant(of: list, matching: find.byType(Scrollable))
        .first,
    maxScrolls: 80,
  );
  await tester.enterText(
    find.byKey(const ValueKey('prospect-search-field')),
    prospect.fullName,
  );
  tester.testTextInput.hide();
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.byKey(ValueKey('prospect-card-${prospect.projectedRank}')),
    200,
    scrollable: find
        .descendant(of: list, matching: find.byType(Scrollable))
        .first,
    maxScrolls: 80,
  );
  await _tapKey(tester, 'prospect-card-${prospect.projectedRank}');
}

Future<void> _openSelectionConfirmation(
  WidgetTester tester,
  RookieProspect prospect,
) async {
  await _openProspect(tester, prospect);
  await _tapKey(tester, 'draft-player-button');
  expect(find.byKey(const ValueKey('confirm-draft-player')), findsOneWidget);
}

Future<void> _dismissSheet(WidgetTester tester) async {
  if (find.byType(BottomSheet).evaluate().isNotEmpty) {
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  }
}

Future<void> _expectSelectedProspect(
  WidgetTester tester,
  RookieProspect prospect,
) async {
  await _openProspect(tester, prospect);
  expect(
    _sheetText(tester),
    matches(RegExp('selected|drafted', caseSensitive: false)),
  );
  final button = find.byKey(const ValueKey('draft-player-button'));
  expect(button, findsOneWidget);
  expect(tester.widget<ButtonStyleButton>(button).onPressed, isNull);
  await _dismissSheet(tester);
}

void _expectHumanTurn(GmCareerController controller, int overall) {
  final career = controller.career!;
  expect(controller.isLoading, isFalse);
  expect(career.draftExecutionState.currentOverallPick, overall);
  expect(career.draftExecutionState.completedSelectionsCount, overall - 1);
  expect(
    career.draftExecutionState.isHumanTurn(
      order: career.draftOrder,
      userTeamId: career.userFranchiseId,
    ),
    isTrue,
  );
}

String _texts(WidgetTester tester, Finder root) {
  final texts = <Text>[
    if (root.evaluate().length == 1 && tester.widget(root) is Text)
      tester.widget<Text>(root),
    ...tester.widgetList<Text>(
      find.descendant(of: root, matching: find.byType(Text)),
    ),
  ];
  return texts
      .map((text) => text.data ?? text.textSpan?.toPlainText() ?? '')
      .join('\n');
}

String _textAt(WidgetTester tester, String key) =>
    _texts(tester, find.byKey(ValueKey(key)));

String _dialogText(WidgetTester tester) =>
    _texts(tester, find.byType(AlertDialog));

String _sheetText(WidgetTester tester) =>
    _texts(tester, find.byType(BottomSheet));

Future<String> _allSheetText(WidgetTester tester) async {
  final sheet = find.byType(BottomSheet);
  final scrollable = find
      .descendant(of: sheet, matching: find.byType(Scrollable))
      .first;
  final text = <String>{};
  for (var step = 0; step < 30; step++) {
    text.addAll(_sheetText(tester).split('\n'));
    final position = tester.state<ScrollableState>(scrollable).position;
    if (position.pixels >= position.maxScrollExtent) {
      final sorted = text.toList()..sort();
      return sorted.join('\n');
    }
    await tester.drag(scrollable, const Offset(0, -240));
    await tester.pumpAndSettle();
  }
  fail('Prospect details did not reach the end after 30 scrolls.');
}

int _orderCount(WidgetTester tester) =>
    tester
        .widget<ListView>(find.byKey(const ValueKey('draft-order-list')))
        .semanticChildCount! -
    1;

Future<void> _expectResults(
  WidgetTester tester,
  RookieProspect first,
  RookieProspect second,
) async {
  await _dismissSheet(tester);
  await _tab(tester, 2);
  final results = find.byKey(const ValueKey('draft-results'));
  expect(results, findsOneWidget);
  final scrollable = find
      .descendant(of: results, matching: find.byType(Scrollable))
      .first;
  final rights = find.byKey(const ValueKey('draft-owned-rights'));
  await tester.scrollUntilVisible(
    rights,
    -240,
    scrollable: scrollable,
    maxScrolls: 100,
  );
  final text = _textAt(tester, 'draft-results');
  expect(text, contains('60 selections'));
  expect(text, contains('30 undrafted prospects'));
  expect(text, contains('Active Roster Players'));
  expect(
    _textAt(tester, 'draft-owned-rights'),
    matches(RegExp('unsigned', caseSensitive: false)),
  );
  final career = tester
      .widget<GmDraftBoardScreen>(find.byType(GmDraftBoardScreen))
      .controller
      .career!;
  for (final prospect in [first, second]) {
    final card = find.byKey(
      ValueKey('prospect-card-${prospect.projectedRank}'),
    );
    await tester.scrollUntilVisible(
      card,
      160,
      scrollable: scrollable,
      maxScrolls: 20,
    );
    expect(_texts(tester, card), contains(prospect.fullName));
    final right = career.draftExecutionState.draftRights[prospect.id.value]!;
    final metadata = _texts(
      tester,
      find.ancestor(of: card, matching: find.byType(Column)).first,
    );
    expect(metadata, contains('Overall #${right.overallPick}'));
    expect(metadata, contains('Round ${(right.overallPick - 1) ~/ 30 + 1}'));
  }
  expect(find.text('Sign Player'), findsNothing);
  expect(tester.takeException(), isNull);
}

Future<void> _expectOrderHistory(
  WidgetTester tester,
  GmCareer career, {
  required bool everyPick,
}) async {
  await _tab(tester, 0);
  await _tapText(tester, 'All (60)');
  expect(_orderCount(tester), 60);
  final list = find.byKey(const ValueKey('draft-order-list'));
  final scrollable = find
      .descendant(of: list, matching: find.byType(Scrollable))
      .first;
  await tester.scrollUntilVisible(
    find.byKey(const ValueKey('draft-pick-1')),
    -240,
    scrollable: scrollable,
    maxScrolls: 80,
  );
  final selections = career.draftExecutionState.selections;
  for (final selection
      in everyPick ? selections : [selections.first, selections.last]) {
    final key = 'draft-pick-${selection.overallPick}';
    await tester.scrollUntilVisible(
      find.byKey(ValueKey(key)),
      200,
      scrollable: scrollable,
      maxScrolls: 80,
    );
    final text = _textAt(tester, key);
    expect(
      text,
      contains(career.draftClass.byId(selection.prospectId)!.fullName),
    );
    expect(text, contains('Round ${selection.round}'));
    expect(text, contains('${selection.pickInRound}'));
  }
}

void _expectUnchangedRosters(GmCareer original, Iterable<String> commits) {
  final initial =
      jsonDecode(GmCareerCodec.encode(original)) as Map<String, dynamic>;
  for (final raw in commits) {
    final snapshot = jsonDecode(raw) as Map<String, dynamic>;
    for (final key in ['league', 'careerProfiles', 'rosterMemberships']) {
      expect(
        snapshot[key],
        initial[key],
        reason: '$key changed during a draft save',
      );
    }
  }
}

class _Fixture {
  _Fixture(this.storage, this.controller);

  final _ObservedStorage storage;
  final GmCareerController controller;

  static Future<_Fixture> create(GmCareer career) async {
    final storage = _ObservedStorage(career);
    final controller = GmCareerController(storage: storage);
    addTearDown(controller.dispose);
    await controller.loadCareer();
    return _Fixture(storage, controller);
  }
}

class _WriteGate {
  final entered = Completer<GmCareer>();
  final release = Completer<void>();
}

class _ObservedStorage implements GmCareerStorage {
  _ObservedStorage(GmCareer initial, {GmCareerStorage? delegate})
    : data = GmCareerCodec.encode(initial),
      delegate =
          delegate ??
          InMemoryGmCareerStorage({'default': GmCareerCodec.encode(initial)});

  final GmCareerStorage delegate;
  final commits = <String>[];
  final _gates = <int, _WriteGate>{};
  String data;
  int attempts = 0;
  int reads = 0;
  int clears = 0;
  int? failAtSelectionCount;
  bool failAfterCommit = false;
  bool failReads = false;

  GmCareer get saved => GmCareerCodec.decode(data);

  List<int> get selectionCounts => [
    for (final raw in commits)
      ((jsonDecode(raw) as Map<String, dynamic>)['draftExecutionState']
                  as Map<String, dynamic>)['selections']
              .length
          as int,
  ];

  _WriteGate gateAt(int selectionCount) {
    final gate = _WriteGate();
    _gates[selectionCount] = gate;
    addTearDown(() {
      if (!gate.release.isCompleted) gate.release.complete();
    });
    return gate;
  }

  @override
  Future<String?> read({String slot = 'default'}) async {
    reads++;
    if (failReads) {
      throw const GmCareerStorageException('Injected draft read failure');
    }
    return delegate.read(slot: slot);
  }

  @override
  Future<void> write(String next, {String slot = 'default'}) async {
    attempts++;
    final candidate = GmCareerCodec.decode(next);
    final count = candidate.draftExecutionState.completedSelectionsCount;
    final gate = _gates.remove(count);
    if (gate != null) {
      gate.entered.complete(candidate);
      await gate.release.future;
    }
    final fail = count == failAtSelectionCount;
    if (fail) failAtSelectionCount = null;
    if (!fail || failAfterCommit) {
      await delegate.write(next, slot: slot);
      data = next;
      commits.add(next);
    }
    if (fail) {
      throw const GmCareerStorageException('Injected draft write failure');
    }
  }

  @override
  Future<void> clear({String slot = 'default'}) async {
    clears++;
    await delegate.clear(slot: slot);
  }

  @override
  Future<bool> hasSave({String slot = 'default'}) =>
      delegate.hasSave(slot: slot);
}

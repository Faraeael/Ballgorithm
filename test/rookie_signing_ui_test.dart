import 'dart:async';

import 'package:basketball_manager/features/career/career_controller.dart';
import 'package:basketball_manager/features/career/career_storage.dart';
import 'package:basketball_manager/features/career/offseason_overview_screen.dart';
import 'package:basketball_manager/features/career/rookie_signing_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simulation_core/simulation_core.dart';

const _seed = 20261028;
const _team = TeamId('team-1');
const _smallViewport = Size(360, 640);
const _largeViewport = Size(393, 852);

void main() {
  late GmCareer completed;

  setUpAll(() {
    completed = _completedCareer(FranchiseSituation.playIn);
  });

  group('M008-T07B rookie signing UI', () {
    testWidgets('1. signing is unavailable before the draft completes', (
      tester,
    ) async {
      _viewport(tester, _smallViewport);
      final initial = GmCareer.fromSetupResult(
        const CareerSetupService().generate(
          const CareerSetupRequest(
            selectedTeamId: _team,
            selectedSituation: FranchiseSituation.playIn,
            seed: _seed,
          ),
        ),
        id: 't07b-incomplete',
      );
      final fixture = await _Fixture.create(initial);
      await _mountOverview(tester, fixture.controller);

      expect(find.byKey(const ValueKey('card-rookie-signing')), findsNothing);
      expect(
        find.byKey(const ValueKey('btn-open-rookie-signing')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('2-4. completed draft exposes owned rights and details', (
      tester,
    ) async {
      _viewport(tester, _smallViewport);
      final fixture = await _Fixture.create(completed);
      await _mountOverview(tester, fixture.controller);
      final summary = _textUnder(tester, 'card-rookie-signing');
      expect(summary, contains('2 drafted prospects'));
      expect(summary, contains('0 signed'));
      expect(summary, contains('2 unsigned'));

      await _openSigning(tester);

      final rights = _userRights(completed);
      expect(rights, hasLength(2));
      for (final right in rights) {
        final selection = completed.draftExecutionState.selections.firstWhere(
          (s) => s.prospectId == right.prospectId,
        );
        final prospect = completed.draftClass.byId(right.prospectId)!;
        final card = _textUnder(
          tester,
          'rookie-right-${selection.overallPick}',
        );
        expect(card, contains(prospect.fullName));
        expect(card, contains(prospect.position.shortName));
        expect(card, contains('Age ${prospect.age}'));
        expect(card, contains('OVR ${prospect.overallRating}'));
        expect(card, contains('Round ${selection.round}'));
        expect(card, contains('Pick #${selection.overallPick}'));
        expect(card, contains('Projected #${prospect.projectedRank}'));
        expect(card, contains(prospect.estimatedPotentialGrade));
        expect(card, contains('Unsigned rights'));
      }
      // Only the human franchise's rights are listed.
      expect(find.byKey(const ValueKey('rookie-right-1')), findsNothing);
      expect(find.byKey(const ValueKey('rookie-right-2')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      '5, 8, 11, 12, 13. standard signing updates roster and counts',
      (tester) async {
        _viewport(tester, _smallViewport);
        final fixture = await _Fixture.create(completed);
        final firstPick = _userRights(completed).first.overallPick;
        final prospect = completed.draftClass.byId(
          _userRights(completed).first.prospectId,
        )!;
        await _mountOverview(tester, fixture.controller);
        await _openSigning(tester);
        await _openSheet(tester, firstPick);

        final sheet = _sheetText(tester);
        expect(sheet, contains('Sign ${prospect.fullName}'));
        expect(sheet, contains('Standard: 12/15'));
        expect(sheet, contains('After signing: Standard 13/15'));

        await _tapSheetKey(tester, 'sign-duration-4');
        await _tapSheetKey(tester, 'confirm-signing');
        await tester.pumpAndSettle();

        expect(fixture.storage.attempts, 1);
        final career = fixture.controller.career!;
        expect(career.userTeam.roster.standardCount, 13);
        expect(career.rookieSigningLedger.length, 1);
        final contract = career.rookieSigningLedger.forPlayer(prospect.id)!;
        expect(contract.category, RosterCategory.standard);
        expect(contract.durationYears, 4);
        expect(career.draftExecutionState.selections.length, 60);
        expect(
          fixture.storage.saved.rookieSigningLedger.length,
          1,
          reason: 'persisted before publish',
        );
        expect(
          _textUnder(tester, 'rookie-signing-summary'),
          contains('1 signed • 1 unsigned'),
        );

        expect(
          find.byKey(const ValueKey('rookie-signing-sheet')),
          findsNothing,
        );
        expect(find.byType(GmRookieSigningScreen), findsOneWidget);
        // Back to the offseason: roster shows the player as a standard rookie.
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.byType(GmRookieSigningScreen), findsNothing);
        expect(
          find.byKey(const ValueKey('offseason-overview-scroll')),
          findsOneWidget,
        );
        await _scrollOverviewTo(tester, find.text(prospect.fullName));
        final tile = _textAt(
          tester,
          find
              .ancestor(
                of: find.text(prospect.fullName),
                matching: find.byType(ListTile),
              )
              .first,
        );
        expect(tile, contains('Rookie • Standard'));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('6, 7. two-way selection offers only 1-2 year durations', (
      tester,
    ) async {
      _viewport(tester, _smallViewport);
      final fixture = await _Fixture.create(completed);
      final firstPick = _userRights(completed).first.overallPick;
      await _mountOverview(tester, fixture.controller);
      await _openSigning(tester);
      await _openSheet(tester, firstPick);

      expect(find.byKey(const ValueKey('sign-duration-4')), findsOneWidget);
      await _tapSheetKey(tester, 'sign-category-two-way');
      expect(find.byKey(const ValueKey('sign-duration-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('sign-duration-2')), findsOneWidget);
      expect(find.byKey(const ValueKey('sign-duration-3')), findsNothing);
      expect(find.byKey(const ValueKey('sign-duration-4')), findsNothing);
      expect(_sheetText(tester), contains('After signing: Standard 12/15'));
      expect(_sheetText(tester), contains('Two-way 1/3'));

      await _tapSheetKey(tester, 'sign-duration-2');
      await _tapSheetKey(tester, 'confirm-signing');
      await tester.pumpAndSettle();

      final career = fixture.controller.career!;
      expect(career.userTeam.roster.twoWayCount, 1);
      expect(career.userTeam.roster.standardCount, 12);
      expect(
        career.rookieSigningLedger.ordered.single.category,
        RosterCategory.twoWay,
      );
      expect(career.rookieSigningLedger.ordered.single.durationYears, 2);
    });

    testWidgets('9. a full category is disabled with a reason', (tester) async {
      _viewport(tester, _smallViewport);
      final full = _expanded(completed, standard: 3);
      final fixture = await _Fixture.create(full);
      await _mountOverview(tester, fixture.controller);
      await _openSigning(tester);
      await _openSheet(tester, _userRights(full).first.overallPick);

      final standardChip = tester.widget<ChoiceChip>(
        find.byKey(const ValueKey('sign-category-standard')),
      );
      expect(standardChip.onSelected, isNull);
      expect(_sheetText(tester), contains('Standard roster is full'));
      final confirm = tester.widget<FilledButton>(
        find.byKey(const ValueKey('confirm-signing')),
      );
      expect(confirm.onPressed, isNull);

      // Two-way is still available for the same prospect.
      final twoWayChip = tester.widget<ChoiceChip>(
        find.byKey(const ValueKey('sign-category-two-way')),
      );
      expect(twoWayChip.onSelected, isNotNull);
    });

    testWidgets('9b. a full two-way pool is disabled with a reason', (
      tester,
    ) async {
      _viewport(tester, _smallViewport);
      final full = _expanded(completed, twoWay: 3);
      final fixture = await _Fixture.create(full);
      await _mountOverview(tester, fixture.controller);
      await _openSigning(tester);
      await _openSheet(tester, _userRights(full).first.overallPick);

      final chip = tester.widget<ChoiceChip>(
        find.byKey(const ValueKey('sign-category-two-way')),
      );
      expect(chip.onSelected, isNull);
      expect(_sheetText(tester), contains('Two-way slots are full'));
    });

    testWidgets('9c. the total offseason limit disables both categories', (
      tester,
    ) async {
      _viewport(tester, _smallViewport);
      final full = _expanded(completed, twoWay: 3, trainingCamp: 6);
      final fixture = await _Fixture.create(full);
      await _mountOverview(tester, fixture.controller);
      await _openSigning(tester);
      await _openSheet(tester, _userRights(full).first.overallPick);

      expect(
        tester
            .widget<ChoiceChip>(
              find.byKey(const ValueKey('sign-category-standard')),
            )
            .onSelected,
        isNull,
      );
      expect(
        tester
            .widget<ChoiceChip>(
              find.byKey(const ValueKey('sign-category-two-way')),
            )
            .onSelected,
        isNull,
      );
      expect(
        _sheetText(tester),
        contains('Offseason roster limit reached (21/21)'),
      );
    });

    testWidgets('10. cancel performs no write', (tester) async {
      _viewport(tester, _smallViewport);
      final fixture = await _Fixture.create(completed);
      await _mountOverview(tester, fixture.controller);
      await _openSigning(tester);
      await _openSheet(tester, _userRights(completed).first.overallPick);

      await _tapSheetKey(tester, 'cancel-signing');
      await tester.pumpAndSettle();

      expect(fixture.storage.attempts, 0);
      expect(fixture.controller.career!.rookieSigningLedger.isEmpty, isTrue);
      expect(fixture.storage.data, GmCareerCodec.encode(completed));
    });

    testWidgets('14, 16. signed rookie is no longer signable', (tester) async {
      _viewport(tester, _smallViewport);
      final fixture = await _Fixture.create(completed);
      final right = _userRights(completed).first;
      await _mountOverview(tester, fixture.controller);
      await _openSigning(tester);
      await _openSheet(tester, right.overallPick);
      await _tapSheetKey(tester, 'confirm-signing');
      await tester.pumpAndSettle();

      expect(
        find.byKey(ValueKey('rookie-sign-button-${right.overallPick}')),
        findsNothing,
      );
      expect(
        _textUnder(tester, 'rookie-right-${right.overallPick}'),
        contains('Signed — Standard'),
      );
      expect(
        _textUnder(tester, 'rookie-signing-summary'),
        contains('1 signed • 1 unsigned'),
      );
    });

    testWidgets('15. draft history remains intact after signing', (
      tester,
    ) async {
      _viewport(tester, _largeViewport);
      final fixture = await _Fixture.create(completed);
      final right = _userRights(completed).first;
      await _mountOverview(tester, fixture.controller);
      await _openSigning(tester);
      await _openSheet(tester, right.overallPick);
      await _tapSheetKey(tester, 'confirm-signing');
      await tester.pumpAndSettle();
      expect(
        fixture.controller.career!.draftExecutionState.selections.length,
        60,
      );

      await tester.pageBack();
      await tester.pumpAndSettle();
      final openDraft = find.byKey(const ValueKey('btn-open-draft-board'));
      await tester.scrollUntilVisible(
        openDraft,
        240,
        scrollable: _overviewScrollable(tester),
      );
      await tester.ensureVisible(openDraft);
      await tester.pumpAndSettle();
      await tester.tap(openDraft);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Results'));
      await tester.pumpAndSettle();

      final results = find.byKey(const ValueKey('draft-results'));
      expect(results, findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('draft-owned-rights')),
        -240,
        scrollable: find
            .descendant(of: results, matching: find.byType(Scrollable))
            .first,
        maxScrolls: 100,
      );
      expect(_textUnder(tester, 'draft-results'), contains('60 selections'));
      final header =
          tester
              .widget<Text>(find.byKey(const ValueKey('draft-owned-rights')))
              .data ??
          '';
      expect(header, contains('1 unsigned'));
      expect(header, contains('1 signed'));
    });

    testWidgets('17. rapid double confirm signs exactly once', (tester) async {
      _viewport(tester, _smallViewport);
      final fixture = await _Fixture.create(completed);
      final right = _userRights(completed).first;
      await _mountOverview(tester, fixture.controller);
      await _openSigning(tester);
      await _openSheet(tester, right.overallPick);

      final gate = Completer<void>();
      fixture.storage.gate = gate;
      await _tapSheetKey(tester, 'confirm-signing');
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('confirm-signing')))
            .onPressed,
        isNull,
      );
      await tester.tap(
        find.byKey(const ValueKey('confirm-signing')),
        warnIfMissed: false,
      );
      await tester.pump();

      gate.complete();
      fixture.storage.gate = null;
      await tester.pumpAndSettle();

      expect(fixture.storage.attempts, 1);
      expect(fixture.controller.career!.rookieSigningLedger.length, 1);
      expect(fixture.storage.saved.rookieSigningLedger.length, 1);
    });

    testWidgets('18. failed write requires reload reconciliation', (
      tester,
    ) async {
      _viewport(tester, _smallViewport);
      final fixture = await _Fixture.create(completed);
      final right = _userRights(completed).first;
      final before = fixture.storage.data;
      await _mountOverview(tester, fixture.controller);
      await _openSigning(tester);
      await _openSheet(tester, right.overallPick);

      fixture.storage.failNextWrite = true;
      await _tapSheetKey(tester, 'confirm-signing');
      await tester.pumpAndSettle();

      expect(fixture.controller.career!.rookieSigningLedger.isEmpty, isTrue);
      expect(fixture.controller.draftRecoveryRequired, isTrue);
      expect(fixture.storage.data, before);
      expect(find.byKey(const ValueKey('signing-error')), findsOneWidget);
      expect(find.byKey(const ValueKey('signing-reload')), findsOneWidget);

      await _tapSheetKey(tester, 'signing-reload');
      await tester.pumpAndSettle();
      expect(fixture.controller.draftRecoveryRequired, isFalse);
      expect(fixture.controller.career!.rookieSigningLedger.isEmpty, isTrue);
      expect(find.byKey(const ValueKey('rookie-signing-sheet')), findsNothing);
      // A fresh sheet can sign normally after reconciliation.
      await _openSheet(tester, right.overallPick);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('confirm-signing')))
            .onPressed,
        isNotNull,
      );
    });

    testWidgets('19. restart preserves signed rookies and contracts', (
      tester,
    ) async {
      _viewport(tester, _smallViewport);
      final fixture = await _Fixture.create(completed);
      final right = _userRights(completed).first;
      final prospect = completed.draftClass.byId(right.prospectId)!;
      await _mountOverview(tester, fixture.controller);
      await _openSigning(tester);
      await _openSheet(tester, right.overallPick);
      await _tapSheetKey(tester, 'confirm-signing');
      await tester.pumpAndSettle();

      final restarted = GmCareerController(storage: fixture.storage);
      addTearDown(restarted.dispose);
      await restarted.loadCareer();
      expect(restarted.career!.rookieSigningLedger.length, 1);
      expect(restarted.career!.userTeam.roster.standardCount, 13);
      await tester.pumpWidget(const SizedBox.shrink());
      await _mountOverview(tester, restarted);
      expect(_textUnder(tester, 'card-rookie-signing'), contains('1 signed'));
      await _scrollOverviewTo(tester, find.text(prospect.fullName));
      expect(
        _textAt(
          tester,
          find
              .ancestor(
                of: find.text(prospect.fullName),
                matching: find.byType(ListTile),
              )
              .first,
        ),
        contains('Rookie • Standard'),
      );
    });

    testWidgets('20. signed rookies never expose hidden potential', (
      tester,
    ) async {
      _viewport(tester, _smallViewport);
      final fixture = await _Fixture.create(completed);
      final right = _userRights(completed).first;
      final prospect = completed.draftClass.byId(right.prospectId)!;
      await _mountOverview(tester, fixture.controller);
      await _openSigning(tester);
      await _openSheet(tester, right.overallPick);

      final card = _textUnder(tester, 'rookie-right-${right.overallPick}');
      expect(card, contains('Est. POT'));
      final sheet = _sheetText(tester);
      expect(sheet, isNot(contains('POT ${prospect.potential}')));
      expect(sheet, isNot(contains(prospect.trajectory.displayName)));

      await _tapSheetKey(tester, 'confirm-signing');
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await _scrollOverviewTo(tester, find.text(prospect.fullName));
      final tile = _textAt(
        tester,
        find
            .ancestor(
              of: find.text(prospect.fullName),
              matching: find.byType(ListTile),
            )
            .first,
      );
      expect(tile, contains('Rookie • Standard'));
      expect(tile, contains('Est. ${prospect.estimatedPotentialGrade}'));
      expect(tile, isNot(contains('POT ${prospect.potential}')));
      expect(tile, isNot(contains(prospect.trajectory.displayName)));
    });

    testWidgets('23. signing surfaces fit 360x640 and 393x852', (tester) async {
      for (final size in [_smallViewport, _largeViewport]) {
        _viewport(tester, size);
        final fixture = await _Fixture.create(completed);
        await _mountOverview(tester, fixture.controller);
        await _openSigning(tester);
        await _openSheet(tester, _userRights(completed).first.overallPick);
        await tester.pumpAndSettle();
        final exception = tester.takeException();
        expect(exception, isNull, reason: '$size: $exception');
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });
  });
}

Widget _app(Widget home) => MaterialApp(
  theme: ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFB4541E)),
  ),
  home: home,
);

void _viewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Finder _overviewScrollable(WidgetTester tester) => find
    .descendant(
      of: find.byKey(const ValueKey('offseason-overview-scroll')),
      matching: find.byType(Scrollable),
    )
    .first;

Future<void> _mountOverview(
  WidgetTester tester,
  GmCareerController controller,
) async {
  await tester.pumpWidget(
    _app(GmOffseasonOverviewScreen(controller: controller)),
  );
  await tester.pumpAndSettle();
}

Future<void> _openSigning(WidgetTester tester) async {
  final button = find.byKey(const ValueKey('btn-open-rookie-signing'));
  await tester.scrollUntilVisible(
    button,
    240,
    scrollable: _overviewScrollable(tester),
  );
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
  expect(find.byType(GmRookieSigningScreen), findsOneWidget);
}

Future<void> _openSheet(WidgetTester tester, int pick) async {
  final button = find.byKey(ValueKey('rookie-sign-button-$pick'));
  await tester.scrollUntilVisible(
    button,
    200,
    scrollable: find
        .descendant(
          of: find.byKey(const ValueKey('rookie-signing-scroll')),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('rookie-signing-sheet')), findsOneWidget);
}

Future<void> _tapSheetKey(WidgetTester tester, String key) async {
  final target = find.byKey(ValueKey(key));
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _scrollOverviewTo(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    200,
    scrollable: _overviewScrollable(tester),
  );
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}

String _textUnder(WidgetTester tester, String key) =>
    _texts(tester, find.byKey(ValueKey(key)));

String _texts(WidgetTester tester, Finder finder) => tester
    .widgetList<Text>(find.descendant(of: finder, matching: find.byType(Text)))
    .map((text) => text.data ?? '')
    .join('\n');

String _textAt(WidgetTester tester, Finder finder) => tester
    .widgetList<Text>(find.descendant(of: finder, matching: find.byType(Text)))
    .map((text) => text.data ?? '')
    .join('\n');

String _sheetText(WidgetTester tester) =>
    _textUnder(tester, 'rookie-signing-sheet');

GmCareer _completedCareer(FranchiseSituation situation) {
  final setup = const CareerSetupService().generate(
    CareerSetupRequest(
      selectedTeamId: _team,
      selectedSituation: situation,
      seed: _seed,
    ),
  );
  var career = GmCareer.fromSetupResult(setup, id: 't07b-${situation.name}');
  const draft = DraftExecutionService();
  career = draft.startDraft(career);
  while (!career.draftExecutionState.isCompleted) {
    career =
        career.draftExecutionState.isHumanTurn(
          order: career.draftOrder,
          userTeamId: career.userFranchiseId,
        )
        ? draft.makeHumanSelection(
            career: career,
            prospectId: career.draftExecutionState
                .availableProspects(career.draftClass)
                .first
                .id,
          )
        : draft.executeAiSelection(career);
  }
  return career;
}

List<DraftRights> _userRights(GmCareer career) =>
    career.draftExecutionState.draftRights.values
        .where((rights) => rights.owningTeamId == career.userFranchiseId)
        .toList()
      ..sort((a, b) => a.overallPick.compareTo(b.overallPick));

GmCareer _expanded(
  GmCareer career, {
  int standard = 0,
  int twoWay = 0,
  int trainingCamp = 0,
}) {
  var roster = career.userTeam.roster;
  final added = <Player>[];
  void add(int count, String prefix, RosterCategory category) {
    for (var i = 0; i < count; i++) {
      final player = _testPlayer('$prefix-$i');
      added.add(player);
      roster = roster.withPlayer(player, category: category);
    }
  }

  add(standard, 'added-std', RosterCategory.standard);
  add(twoWay, 'added-tw', RosterCategory.twoWay);
  add(trainingCamp, 'added-tc', RosterCategory.trainingCamp);
  return career.withUpdatedTeam(
    career.userTeam.copyWith(roster: roster),
    careerProfiles: LeagueCareerProfiles(
      leagueSeed: career.careerProfiles.leagueSeed,
      profiles: {
        ...career.careerProfiles.profiles,
        for (final player in added)
          player.id.value: PlayerCareerProfile(
            playerId: player.id,
            age: 23,
            potential: 60,
            trajectory: DevelopmentTrajectory.steady,
          ),
      },
    ),
  );
}

Player _testPlayer(String id) => Player(
  id: PlayerId(id),
  firstName: 'Added',
  lastName: id,
  position: Position.sg,
  attributes: PlayerAttributes(
    insideScoring: 50,
    midrange: 50,
    threePoint: 50,
    freeThrow: 50,
    passing: 50,
    ballHandling: 50,
    perimeterDefense: 50,
    interiorDefense: 50,
    rebounding: 50,
    athleticism: 50,
    stamina: 50,
    basketballIQ: 50,
  ),
);

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

class _ObservedStorage implements GmCareerStorage {
  _ObservedStorage(GmCareer initial)
    : data = GmCareerCodec.encode(initial),
      delegate = InMemoryGmCareerStorage({
        'default': GmCareerCodec.encode(initial),
      });

  final GmCareerStorage delegate;
  String data;
  int attempts = 0;
  bool failNextWrite = false;
  Completer<void>? gate;

  GmCareer get saved => GmCareerCodec.decode(data);

  @override
  Future<String?> read({String slot = 'default'}) => delegate.read(slot: slot);

  @override
  Future<void> write(String next, {String slot = 'default'}) async {
    attempts++;
    final pending = gate;
    if (pending != null) await pending.future;
    if (failNextWrite) {
      failNextWrite = false;
      throw const GmCareerStorageException('Injected signing write failure');
    }
    await delegate.write(next, slot: slot);
    data = next;
  }

  @override
  Future<void> clear({String slot = 'default'}) => delegate.clear(slot: slot);

  @override
  Future<bool> hasSave({String slot = 'default'}) =>
      delegate.hasSave(slot: slot);
}

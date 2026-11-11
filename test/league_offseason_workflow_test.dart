import 'dart:async';

import 'package:basketball_manager/features/career/career_controller.dart';
import 'package:basketball_manager/features/career/career_storage.dart';
import 'package:basketball_manager/features/career/league_readiness_screen.dart';
import 'package:basketball_manager/features/career/offseason_overview_screen.dart';
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

  group('M008-T07D league signing workflow', () {
    testWidgets('1. activation is hidden before the draft completes', (
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
        id: 't07d-incomplete',
      );
      final fixture = await _Fixture.create(initial);
      await _mountOverview(tester, fixture.controller);

      expect(find.byKey(const ValueKey('card-league-signings')), findsNothing);
      expect(
        find.byKey(const ValueKey('btn-resolve-league-signings')),
        findsNothing,
      );
      await _scrollOverviewTo(
        tester,
        find.byKey(const ValueKey('card-league-readiness')),
      );
      expect(
        find.byKey(const ValueKey('card-league-readiness')),
        findsOneWidget,
      );
    });

    testWidgets('2-3. confirmation shows counts and cancel writes nothing', (
      tester,
    ) async {
      _viewport(tester, _smallViewport);
      final fixture = await _Fixture.create(completed);
      await _mountOverview(tester, fixture.controller);
      await _scrollOverviewTo(
        tester,
        find.byKey(const ValueKey('card-league-signings')),
      );

      expect(
        _textUnder(tester, 'league-signings-progress'),
        contains('0 / 58'),
      );
      await _tapKey(tester, 'btn-resolve-league-signings');
      final dialog = _dialogText(tester);
      expect(dialog, contains('29 AI franchises'));
      expect(dialog, contains('58 AI-owned draft rights'));
      expect(dialog, contains('0 decisions already evaluated'));
      expect(dialog, contains('58 remaining'));
      expect(dialog, contains('keep its draft rights unsigned'));

      await _tapKey(tester, 'cancel-resolve-signings');
      expect(fixture.storage.attempts, 0);
      expect(fixture.controller.career!.aiRookieSigning.isEmpty, isTrue);
    });

    testWidgets('4-9. processing completes every AI right exactly once', (
      tester,
    ) async {
      _viewport(tester, _smallViewport);
      final fixture = await _Fixture.create(completed);
      await _mountOverview(tester, fixture.controller);
      await _scrollOverviewTo(
        tester,
        find.byKey(const ValueKey('card-league-signings')),
      );

      await _tapKey(tester, 'btn-resolve-league-signings');
      await _tapKey(tester, 'confirm-resolve-signings');
      await tester.pumpAndSettle();

      final career = fixture.controller.career!;
      final report = LeagueReadinessReport.fromCareer(career);
      expect(fixture.storage.attempts, 58);
      expect(career.aiRookieSigning.length, 58);
      expect(report.pendingAiDecisions, 0);
      expect(
        _textUnder(tester, 'league-signings-progress'),
        contains('58 / 58'),
      );
      expect(
        find.byKey(const ValueKey('league-signings-complete')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('btn-resolve-league-signings')),
            )
            .onPressed,
        isNull,
      );
      final breakdown = _textUnder(tester, 'league-signings-breakdown');
      expect(breakdown, contains('${report.aiStandardSignings} standard'));
      expect(breakdown, contains('${report.aiTwoWaySignings} two-way'));
      expect(breakdown, contains('${report.aiDeferredRights} deferred'));

      for (final right in career.draftExecutionState.draftRights.values.where(
        (right) => right.owningTeamId == career.userFranchiseId,
      )) {
        expect(career.aiRookieSigning.hasDecision(right.prospectId), isFalse);
        expect(career.rookieSigningLedger.isSigned(right.prospectId), isFalse);
      }

      final attempts = fixture.storage.attempts;
      await fixture.controller.advanceAiRookieSigning();
      expect(fixture.storage.attempts, attempts);
      expect(career.aiRookieSigning.length, 58);
    });

    testWidgets('10. a partially processed career resumes without replay', (
      tester,
    ) async {
      _viewport(tester, _smallViewport);
      final partial = _applyDecisions(completed, 7);
      final fixture = await _Fixture.create(partial);
      await _mountOverview(tester, fixture.controller);
      await _scrollOverviewTo(
        tester,
        find.byKey(const ValueKey('card-league-signings')),
      );

      expect(
        _textUnder(tester, 'league-signings-progress'),
        contains('7 / 58'),
      );
      expect(
        _textUnder(tester, 'btn-resolve-league-signings'),
        contains('Resume League Rookie Signings'),
      );
      await _tapKey(tester, 'btn-resolve-league-signings');
      await _tapKey(tester, 'confirm-resolve-signings');
      await tester.pumpAndSettle();

      expect(fixture.storage.attempts, 51);
      expect(fixture.controller.career!.aiRookieSigning.length, 58);
      expect(fixture.storage.saved.aiRookieSigning.length, 58);
    });

    testWidgets('5-6. progress updates only for persisted decisions', (
      tester,
    ) async {
      _viewport(tester, _smallViewport);
      final fixture = await _Fixture.create(completed);
      await _mountOverview(tester, fixture.controller);
      await _scrollOverviewTo(
        tester,
        find.byKey(const ValueKey('card-league-signings')),
      );

      final gate = Completer<void>();
      fixture.storage.gateAtAttempt = 5;
      fixture.storage.gate = gate;
      await _tapKey(tester, 'btn-resolve-league-signings');
      await _tapKey(tester, 'confirm-resolve-signings');

      expect(
        _textUnder(tester, 'league-signings-progress'),
        contains('4 / 58'),
      );
      expect(fixture.controller.career!.aiRookieSigning.length, 4);
      expect(fixture.storage.saved.aiRookieSigning.length, 4);

      gate.complete();
      fixture.storage.gate = null;
      await tester.pumpAndSettle();
      expect(fixture.controller.career!.aiRookieSigning.length, 58);
    });

    testWidgets('11. a failed write blocks processing until reload', (
      tester,
    ) async {
      _viewport(tester, _smallViewport);
      final fixture = await _Fixture.create(completed);
      await _mountOverview(tester, fixture.controller);
      await _scrollOverviewTo(
        tester,
        find.byKey(const ValueKey('card-league-signings')),
      );

      fixture.storage.failAtAttempt = 3;
      await _tapKey(tester, 'btn-resolve-league-signings');
      await _tapKey(tester, 'confirm-resolve-signings');
      await tester.pumpAndSettle();

      expect(fixture.controller.draftRecoveryRequired, isTrue);
      expect(fixture.controller.career!.aiRookieSigning.length, 2);
      expect(fixture.storage.saved.aiRookieSigning.length, 2);
      expect(
        find.byKey(const ValueKey('btn-league-signings-reload')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('btn-resolve-league-signings')),
            )
            .onPressed,
        isNull,
      );

      await _tapKey(tester, 'btn-league-signings-reload');
      await tester.pumpAndSettle();
      expect(fixture.controller.draftRecoveryRequired, isFalse);
      expect(fixture.controller.career!.aiRookieSigning.length, 2);
      await _scrollOverviewToTop(tester);
      await _scrollOverviewTo(
        tester,
        find.byKey(const ValueKey('card-league-signings')),
      );
      expect(
        _textUnder(tester, 'btn-resolve-league-signings'),
        contains('Resume League Rookie Signings'),
      );

      await _tapKey(tester, 'btn-resolve-league-signings');
      await _tapKey(tester, 'confirm-resolve-signings');
      await tester.pumpAndSettle();
      expect(fixture.controller.career!.aiRookieSigning.length, 58);
    });

    testWidgets('12. persisted decisions survive a restart', (tester) async {
      _viewport(tester, _smallViewport);
      final fixture = await _Fixture.create(completed);
      await _mountOverview(tester, fixture.controller);
      await _scrollOverviewTo(
        tester,
        find.byKey(const ValueKey('card-league-signings')),
      );
      await _tapKey(tester, 'btn-resolve-league-signings');
      await _tapKey(tester, 'confirm-resolve-signings');
      await tester.pumpAndSettle();

      final restarted = GmCareerController(storage: fixture.storage);
      addTearDown(restarted.dispose);
      await restarted.loadCareer();
      expect(restarted.career!.aiRookieSigning.length, 58);
      await tester.pumpWidget(const SizedBox.shrink());
      await _mountOverview(tester, restarted);
      await _scrollOverviewTo(
        tester,
        find.byKey(const ValueKey('card-league-signings')),
      );
      expect(
        _textUnder(tester, 'league-signings-progress'),
        contains('58 / 58'),
      );
    });
  });

  group('M008-T07D league readiness dashboard', () {
    testWidgets('13-18. dashboard lists franchises with derived readiness', (
      tester,
    ) async {
      _viewport(tester, _largeViewport);
      final expanded = _expandTeam(
        completed,
        const TeamId('team-2'),
        standard: 1,
        twoWay: 3,
      );
      final fixture = await _Fixture.create(expanded);
      final report = LeagueReadinessReport.fromCareer(expanded);
      await _mountOverview(tester, fixture.controller);
      await _openReadiness(tester);

      expect(
        find.byKey(const ValueKey('league-readiness-summary')),
        findsOneWidget,
      );
      expect(
        _textUnder(tester, 'readiness-counts'),
        contains('${report.readyCount} ready'),
      );
      expect(
        _textUnder(tester, 'readiness-shortage'),
        contains('${report.totalStandardShortage}'),
      );
      expect(_textUnder(tester, 'readiness-human'), contains('Aurora Comets'));
      expect(
        find.byKey(const ValueKey('readiness-team-team-1')),
        findsOneWidget,
      );

      final team2 = find.byKey(const ValueKey('readiness-team-team-2'));
      await tester.scrollUntilVisible(
        team2,
        240,
        scrollable: _readinessScrollable(tester),
      );
      await tester.ensureVisible(team2);
      await tester.pumpAndSettle();
      final team2Text = _texts(tester, team2);
      expect(team2Text, contains('Standard 13/15'));
      expect(team2Text, contains('Two-way 3/3'));
      expect(team2Text, contains('NOT READY'));
      expect(team2Text, contains('Needs 1 standard player'));
      expect(team2Text, isNot(contains('Needs 0')));
      expect(
        _textUnder(tester, 'readiness-need-team-2'),
        contains('Needs 1 standard player'),
      );

      final team30 = find.byKey(const ValueKey('readiness-team-team-30'));
      await tester.scrollUntilVisible(
        team30,
        300,
        scrollable: _readinessScrollable(tester),
      );
      expect(team30, findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('17. deferred and pending decisions are distinguishable', (
      tester,
    ) async {
      _viewport(tester, _largeViewport);
      final partial = _applyDecisions(completed, 20);
      final report = LeagueReadinessReport.fromCareer(partial);
      expect(report.aiDeferredRights, greaterThan(0));
      expect(report.pendingAiDecisions, greaterThan(0));

      final fixture = await _Fixture.create(partial);
      await _mountOverview(tester, fixture.controller);
      await _openReadiness(tester);
      expect(
        _textUnder(tester, 'readiness-ai-pending'),
        contains('${report.pendingAiDecisions} of ${report.totalAiRights}'),
      );
      expect(
        _textUnder(tester, 'readiness-ai-signings'),
        contains('${report.aiDeferredRights} deferred'),
      );
    });

    testWidgets('18-19. franchise details are read-only and public-only', (
      tester,
    ) async {
      _viewport(tester, _largeViewport);
      final right = _userRights(completed).first;
      final unsignedRight = _userRights(completed).firstWhere(
        (candidate) => candidate.prospectId != right.prospectId,
      );
      final prospect = completed.draftClass.byId(right.prospectId)!;
      final humanSigned = const RookieSigningService().signDraftedRookie(
        career: completed,
        teamId: _team,
        prospectId: right.prospectId,
        category: RosterCategory.standard,
        durationYears: 3,
      );
      final fixture = await _Fixture.create(humanSigned);
      await _mountOverview(tester, fixture.controller);
      await _openReadiness(tester);

      final humanCard = find.byKey(const ValueKey('readiness-team-team-1'));
      await tester.scrollUntilVisible(
        humanCard,
        200,
        scrollable: _readinessScrollable(tester),
      );
      await tester.tap(humanCard);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(
          ValueKey('detail-unsigned-${unsignedRight.prospectId.value}'),
        ),
        200,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('franchise-detail-sheet')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();

      final sheet = _textUnder(tester, 'franchise-detail-sheet');
      expect(sheet, contains('Signed Drafted Rookies (1)'));
      expect(sheet, contains('Unsigned Drafted Rights (1)'));
      expect(sheet, contains('Unsigned rights'));
      expect(sheet, isNot(contains('Pending evaluation')));
      expect(sheet, contains(prospect.fullName));
      expect(sheet, contains('Standard players'));
      expect(sheet, contains('13/15'));
      expect(sheet, contains('PG'));
      expect(sheet, isNot(contains('POT ${prospect.potential}')));
      expect(sheet, isNot(contains(prospect.trajectory.displayName)));
      expect(find.byType(Slider), findsNothing);
      expect(find.byType(Switch), findsNothing);
    });
  });

  group('M008-T07D deterministic evidence', () {
    for (final situation in FranchiseSituation.values) {
      testWidgets('${situation.name}: controller workflow evidence', (
        tester,
      ) async {
        _viewport(tester, _largeViewport);
        final career = _completedCareer(situation);
        final fixture = await _Fixture.create(career);
        await fixture.controller.advanceAiRookieSigning();
        final report = LeagueReadinessReport.fromCareer(
          fixture.controller.career!,
        );
        final human = report.userTeam;
        // ignore: avoid_print
        print(
          'T07D ${situation.name}: evaluated=${report.evaluatedAiDecisions} '
          'standard=${report.aiStandardSignings} '
          'twoWay=${report.aiTwoWaySignings} '
          'deferred=${report.aiDeferredRights} '
          'aiReady=${report.aiReadyCount} '
          'aiBelowMin=${report.aiBelowMinimumCount} '
          'shortage=${report.totalStandardShortage} '
          'humanStd=${human.standardCount} '
          'humanShortage=${human.standardShortage} '
          'humanUnsigned=${human.unsignedDraftedRights}',
        );

        expect(report.evaluatedAiDecisions, 58);
        expect(report.pendingAiDecisions, 0);
        expect(report.aiReadyCount + report.aiNotReadyCount, 29);
        expect(report.userTeam.signedDraftedRookies, 0);
        expect(report.userTeam.unsignedDraftedRights, 2);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('M008-T07D mobile layout', () {
    testWidgets('23. 360x640 and 393x852 render without overflow', (
      tester,
    ) async {
      for (final size in [_smallViewport, _largeViewport]) {
        _viewport(tester, size);
        final fixture = await _Fixture.create(completed);
        await _mountOverview(tester, fixture.controller);
        await _openReadiness(tester);
        final humanCard = find.byKey(const ValueKey('readiness-team-team-1'));
        await tester.ensureVisible(humanCard);
        await tester.tap(humanCard);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('franchise-detail-sheet')),
          findsOneWidget,
        );
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

Finder _readinessScrollable(WidgetTester tester) => find
    .descendant(
      of: find.byKey(const ValueKey('league-readiness-scroll')),
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

Future<void> _scrollOverviewToTop(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.drag(_overviewScrollable(tester), const Offset(0, 600));
    await tester.pumpAndSettle();
  }
}

Future<void> _scrollOverviewTo(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    240,
    scrollable: _overviewScrollable(tester),
  );
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  final target = find.byKey(ValueKey(key));
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _openReadiness(WidgetTester tester) async {
  final button = find.byKey(const ValueKey('btn-open-league-readiness'));
  await tester.scrollUntilVisible(
    button,
    240,
    scrollable: _overviewScrollable(tester),
  );
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
  expect(find.byType(GmLeagueReadinessScreen), findsOneWidget);
}

String _texts(WidgetTester tester, Finder finder) {
  final values = <String>[];
  for (final element in finder.evaluate()) {
    final widget = element.widget;
    if (widget is Text && widget.data != null) values.add(widget.data!);
  }
  values.addAll(
    tester
        .widgetList<Text>(
          find.descendant(of: finder, matching: find.byType(Text)),
        )
        .map((text) => text.data ?? ''),
  );
  return values.where((value) => value.isNotEmpty).join('\n');
}

String _textUnder(WidgetTester tester, String key) =>
    _texts(tester, find.byKey(ValueKey(key)));

String _dialogText(WidgetTester tester) => tester
    .widgetList<Text>(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(Text),
      ),
    )
    .map((text) => text.data ?? '')
    .join('\n');

GmCareer _completedCareer(FranchiseSituation situation) {
  final setup = const CareerSetupService().generate(
    CareerSetupRequest(
      selectedTeamId: _team,
      selectedSituation: situation,
      seed: _seed,
    ),
  );
  var career = GmCareer.fromSetupResult(setup, id: 't07d-${situation.name}');
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

GmCareer _applyDecisions(GmCareer career, int count) {
  const service = RookieAiSigningService();
  var current = service.initialize(career);
  for (var i = 0; i < count; i++) {
    current = service.applyNextDecision(current);
  }
  return current;
}

GmCareer _expandTeam(
  GmCareer career,
  TeamId teamId, {
  int standard = 0,
  int twoWay = 0,
}) {
  final team = career.league.teams.firstWhere(
    (candidate) => candidate.id == teamId,
  );
  var roster = team.roster;
  final added = <Player>[];
  void add(int count, RosterCategory category, String prefix) {
    for (var i = 0; i < count; i++) {
      final player = Player(
        id: PlayerId('$prefix-${teamId.value}-$i'),
        firstName: 'Added',
        lastName: '$prefix$i',
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
      added.add(player);
      roster = roster.withPlayer(player, category: category);
    }
  }

  add(standard, RosterCategory.standard, 'std');
  add(twoWay, RosterCategory.twoWay, 'tw');
  final updated = team.copyWith(roster: roster);
  return career.copyWith(
    league: League.create(
      id: career.league.id,
      name: career.league.name,
      config: career.league.config,
      teams: [
        for (final candidate in career.league.teams)
          candidate.id == teamId ? updated : candidate,
      ],
      enforceRosterSize: false,
    ),
    careerProfiles: LeagueCareerProfiles(
      leagueSeed: career.careerProfiles.leagueSeed,
      profiles: {
        ...career.careerProfiles.profiles,
        for (final player in added)
          player.id.value: PlayerCareerProfile(
            playerId: player.id,
            age: 24,
            potential: 60,
            trajectory: DevelopmentTrajectory.steady,
          ),
      },
    ),
  );
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

class _ObservedStorage implements GmCareerStorage {
  _ObservedStorage(GmCareer initial)
    : data = GmCareerCodec.encode(initial),
      delegate = InMemoryGmCareerStorage({
        'default': GmCareerCodec.encode(initial),
      });

  final GmCareerStorage delegate;
  String data;
  int attempts = 0;
  int? failAtAttempt;
  int? gateAtAttempt;
  Completer<void>? gate;

  GmCareer get saved => GmCareerCodec.decode(data);

  @override
  Future<String?> read({String slot = 'default'}) => delegate.read(slot: slot);

  @override
  Future<void> write(String next, {String slot = 'default'}) async {
    attempts++;
    final gateNow = attempts == gateAtAttempt ? gate : null;
    if (gateNow != null) await gateNow.future;
    if (attempts == failAtAttempt) {
      failAtAttempt = null;
      throw const GmCareerStorageException('Injected league write failure');
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

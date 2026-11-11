import 'dart:async';
import 'dart:convert';

import 'package:basketball_manager/app.dart';
import 'package:basketball_manager/features/career/career_storage.dart';
import 'package:basketball_manager/features/career/offseason_overview_screen.dart';
import 'package:basketball_manager/features/season/season_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simulation_core/simulation_core.dart';

const _config = GenerationConfig(seed: 20261028);

void _useSmallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

class _GatedCareerStorage extends InMemoryGmCareerStorage {
  _GatedCareerStorage(String initialJson) : super({'default': initialJson});

  final writeStarted = Completer<void>();
  final releaseWrite = Completer<void>();
  bool _gateNextWrite = true;

  @override
  Future<void> write(String data, {String slot = 'default'}) async {
    if (_gateNextWrite) {
      _gateNextWrite = false;
      writeStarted.complete();
      await releaseWrite.future;
    }
    await super.write(data, slot: slot);
  }
}

void main() {
  late League league;
  const careerSetupService = CareerSetupService();

  setUpAll(() {
    league = const LeagueGenerator().generate(_config);
  });

  group('M008-T05: Rookie Draft Board UI & Persistence Flow', () {
    testWidgets(
      'Owned career route finishes queued draft saves after navigation away',
      (tester) async {
        _useSmallViewport(tester);
        final career = GmCareer.fromSetupResult(
          careerSetupService.generate(
            const CareerSetupRequest(
              selectedTeamId: TeamId('team-1'),
              selectedSituation: FranchiseSituation.contender,
              seed: 20261028,
            ),
          ),
        );
        final originalSave = GmCareerCodec.encode(career);
        final storage = _GatedCareerStorage(originalSave);
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: FilledButton(
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) =>
                          GmOffseasonOverviewRoute(storage: storage),
                    ),
                  ),
                  child: const Text('Open Career'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open Career'));
        await tester.pumpAndSettle();
        final controller = tester
            .widget<GmOffseasonOverviewScreen>(
              find.byType(GmOffseasonOverviewScreen),
            )
            .controller;
        await tester.tap(find.byKey(const ValueKey('card-draft-entitlement')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('draft-start-button')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('confirm-start-draft')));
        await tester.pump();
        expect(storage.writeStarted.isCompleted, isTrue);
        expect(await storage.read(), originalSave);
        final settled = controller.commandsSettled;

        final navigator = tester.state<NavigatorState>(find.byType(Navigator));
        navigator.pop();
        await tester.pumpAndSettle();
        navigator.pop();
        await tester.pumpAndSettle();
        expect(find.text('Open Career'), findsOneWidget);

        storage.releaseWrite.complete();
        await settled;
        await tester.pumpAndSettle();
        final saved = GmCareerCodec.decode((await storage.read())!);
        expect(saved.draftExecutionState.completedSelectionsCount, 29);
        expect(saved.draftExecutionState.currentOverallPick, 30);
        expect(
          saved.draftExecutionState.isHumanTurn(
            order: saved.draftOrder,
            userTeamId: saved.userFranchiseId,
          ),
          isTrue,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '12 & 13. Reopening career preserves prospects without regeneration & leaves M007 save untouched',
      (tester) async {
        _useSmallViewport(tester);

        final seasonStorage = InMemorySeasonStorage();
        final careerStorage = InMemoryGmCareerStorage();
        // 1. Launch app and create career
        await tester.pumpWidget(
          BasketballManagerApp(
            league: league,
            storage: seasonStorage,
            careerStorage: careerStorage,
            seasonMode: true,
            seedProvider: () => 20261028,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('open-career-preview')));
        await tester.pumpAndSettle();

        // Select team-1
        await tester.tap(
          find.byKey(const ValueKey('career-team-option-team-1')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('next-situation-button')));
        await tester.pumpAndSettle();

        // Select Tanking
        await tester.tap(find.byKey(const ValueKey('situation-card-tanking')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('generate-career-preview-button')),
        );
        await tester.pumpAndSettle();

        // Drag to reveal start button
        await tester.drag(
          find.byKey(const ValueKey('career-preview-scroll')),
          const Offset(0, -1500),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('start-career-button')));
        await tester.pumpAndSettle();

        // Confirm career creation dialog
        expect(
          find.byKey(const ValueKey('confirm-start-career-button')),
          findsOneWidget,
        );
        await tester.tap(
          find.byKey(const ValueKey('confirm-start-career-button')),
        );
        await tester.pumpAndSettle();

        // Offseason overview is now open
        expect(find.byType(GmOffseasonOverviewScreen), findsOneWidget);

        // Inspect saved career data
        final savedRaw = await careerStorage.read();
        expect(savedRaw, isNotNull);
        final initialSavedCareer = GmCareerCodec.decode(savedRaw!);
        final initialTopProspect = initialSavedCareer.draftClass.rankedFirst;

        // Now write an M007 save sentinel into seasonStorage to verify isolation
        await seasonStorage.write('{"m007-sentinel": "untouched-data"}');
        expect(await seasonStorage.read(), isNotNull);

        // 2. Restart app
        await tester.pumpWidget(
          BasketballManagerApp(
            league: league,
            storage: seasonStorage,
            careerStorage: careerStorage,
            seasonMode: true,
            seedProvider: () => 20261028,
          ),
        );
        await tester.pumpAndSettle();

        // Reopens directly into Offseason Overview
        expect(find.byType(GmOffseasonOverviewScreen), findsOneWidget);
        // Scroll down until Rookie Draft module is visible
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('btn-open-draft-board')),
          160,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('btn-open-draft-board')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const ValueKey('btn-open-draft-board')));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Prospects (90)'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text(initialTopProspect.fullName),
          200,
          scrollable: find
              .descendant(
                of: find.byKey(const ValueKey('prospect-list')),
                matching: find.byType(Scrollable),
              )
              .first,
        );

        // Prospect class was NOT regenerated
        expect(find.text(initialTopProspect.fullName), findsOneWidget);

        // 13. Verify M007 save was never touched
        final seasonRaw = await seasonStorage.read();
        expect(seasonRaw, equals('{"m007-sentinel": "untouched-data"}'));
      },
    );

    test(
      '11. Storage-level migration from schema v1 to v2 preserves career state and synthesizes draft class',
      () async {
        final careerStorage = InMemoryGmCareerStorage();

        final setupResult = careerSetupService.generate(
          const CareerSetupRequest(
            selectedTeamId: TeamId('team-3'),
            selectedSituation: FranchiseSituation.playoff,
            seed: 20261028,
          ),
        );
        final careerV2 = GmCareer.fromSetupResult(setupResult);
        final rawV2Map =
            jsonDecode(GmCareerCodec.encode(careerV2)) as Map<String, dynamic>;

        // Strip v2 draft fields to produce real v1 payload
        final rawV1Map = Map<String, dynamic>.from(rawV2Map)
          ..['schemaVersion'] = 1
          ..remove('draftOrder')
          ..remove('draftClass');

        await careerStorage.write(jsonEncode(rawV1Map));

        // Read through storage
        final loadedJson = await careerStorage.read();
        expect(loadedJson, isNotNull);

        final migrated = GmCareerCodec.decode(loadedJson!);
        expect(migrated.schemaVersion, GmCareer.currentSchemaVersion);
        expect(migrated.userFranchiseId, const TeamId('team-3'));
        expect(migrated.originalSituation, FranchiseSituation.playoff);
        expect(migrated.userOpeningDraftPick, 20);
        expect(migrated.draftOrder.totalPicks, 60);
        expect(migrated.draftClass.length, 90);
        expect(
          migrated.draftOrder.pickAt(20).currentOwnerTeamId,
          const TeamId('team-3'),
        );
      },
    );
  });
}

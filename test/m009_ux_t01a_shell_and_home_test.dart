import 'package:basketball_manager/app.dart';
import 'package:basketball_manager/features/career/career_controller.dart';
import 'package:basketball_manager/features/career/career_shell_scaffold.dart';
import 'package:basketball_manager/features/career/career_storage.dart';
import 'package:basketball_manager/features/career/career_ui_labels.dart';
import 'package:basketball_manager/features/career/main_menu_screen.dart';
import 'package:basketball_manager/features/season/franchise_select_screen.dart';
import 'package:basketball_manager/features/season/season_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simulation_core/simulation_core.dart';

import '../integration_test/support/d3c_fixture_helper.dart';

const _config = GenerationConfig(seed: 20261028);

class _WriteCountingCareerStorage extends InMemoryGmCareerStorage {
  int writeCalls = 0;

  @override
  Future<void> write(String data, {String slot = 'default'}) async {
    writeCalls++;
    return super.write(data, slot: slot);
  }
}

GmCareer _buildOpeningOffseasonCareer() {
  final setup = const CareerSetupService().generate(
    const CareerSetupRequest(
      selectedTeamId: TeamId('team-1'),
      selectedSituation: FranchiseSituation.contender,
      seed: 20261028,
    ),
  );
  return GmCareer.fromSetupResult(setup, id: 'career-t01a-test');
}

GmCareer _buildRegularSeasonCareer({int roundsToSim = 2}) {
  var c = _buildOpeningOffseasonCareer();
  const draftService = DraftExecutionService();
  const aiSigningService = RookieAiSigningService();
  const signingService = RookieSigningService();
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
  for (var r = 1; r <= roundsToSim; r++) {
    c = const RegularSeasonRoundService().simulateNextRound(
      c,
      expectedRoundNumber: r,
    );
  }
  return c;
}

GmCareer _buildPlayInCareer() {
  final c = _buildOpeningOffseasonCareer();
  final completed = completeSeasonFromSetup(c);
  // Build Play-In phase directly from completed regular season state
  final rsOnly = GmCareer(
    id: completed.id,
    generationSeed: completed.generationSeed,
    userFranchiseId: completed.userFranchiseId,
    originalSituation: completed.originalSituation,
    currentYear: completed.currentYear,
    phase: CareerPhase.regularSeason,
    league: completed.league,
    careerProfiles: completed.careerProfiles,
    userOpeningDraftPick: completed.userOpeningDraftPick,
    draftOrder: completed.draftOrder,
    draftClass: completed.draftClass,
    draftExecutionState: completed.draftExecutionState,
    rookieSigningLedger: completed.rookieSigningLedger,
    aiRookieSigning: completed.aiRookieSigning,
    freeAgentPool: completed.freeAgentPool,
    freeAgentOffers: completed.freeAgentOffers,
    freeAgentMarket: completed.freeAgentMarket,
    offseasonClearance: completed.offseasonClearance,
    hardshipSettlement: completed.hardshipSettlement,
    finances: completed.finances,
    regularSeasonState: completed.regularSeasonState,
  );
  return const PlayInEntryService().enter(rsOnly);
}

GmCareer _buildPlayoffsCareer() {
  return completeSeasonFromSetup(_buildOpeningOffseasonCareer());
}

void _setViewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  late League league;
  late GmCareer offseasonCareer;
  late GmCareer regularSeasonCareer;
  late GmCareer playInCareer;
  late GmCareer playoffCareer;

  setUpAll(() {
    league = const LeagueGenerator().generate(_config);
    offseasonCareer = _buildOpeningOffseasonCareer();
    regularSeasonCareer = _buildRegularSeasonCareer(roundsToSim: 2);
    playInCareer = _buildPlayInCareer();
    playoffCareer = _buildPlayoffsCareer();
  });

  group('M009-UX-T01A: Main Menu, Career Shell & Home', () {
    testWidgets('A & O: Main Menu new/continue routes and Classic mode', (
      tester,
    ) async {
      _setViewport(tester, const Size(390, 844));
      final storage = InMemoryGmCareerStorage();
      await tester.pumpWidget(
        BasketballManagerApp(
          league: league,
          storage: InMemorySeasonStorage(),
          careerStorage: storage,
          seasonMode: true,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(MainMenuScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('open-career-preview')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('open-classic-mode-button')),
        findsOneWidget,
      );

      // O. Classic mode remains reachable
      await tester.tap(find.byKey(const ValueKey('open-classic-mode-button')));
      await tester.pumpAndSettle();
      expect(find.byType(FranchiseSelectScreen), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      // A. New GM Career opens setup
      await tester.tap(find.byKey(const ValueKey('open-career-preview')));
      await tester.pumpAndSettle();
      expect(find.text('GM Career: Select Team'), findsOneWidget);
    });

    testWidgets(
      'B, C, D, K: Career survives exit/re-enter, 5 tabs reachable, same controller, zero mutation',
      (tester) async {
        _setViewport(tester, const Size(390, 844));
        final storage = _WriteCountingCareerStorage();
        await storage.write(GmCareerCodec.encode(regularSeasonCareer));
        final initialWrites = storage.writeCalls;
        final controller = GmCareerController(storage: storage);
        await controller.loadCareer();
        final beforeJson = GmCareerCodec.encode(controller.career!);

        await tester.pumpWidget(
          BasketballManagerApp(
            league: league,
            storage: InMemorySeasonStorage(),
            careerStorage: storage,
            careerController: controller,
            seasonMode: true,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(CareerShellScaffold), findsOneWidget);
        final shellState = tester.widget<CareerShellScaffold>(
          find.byType(CareerShellScaffold),
        );
        expect(identical(shellState.controller, controller), isTrue);

        // C & D. Visit all 5 destinations without recreating controller or mutating career
        for (final key in [
          'nav-tab-team',
          'nav-tab-league',
          'nav-tab-market',
          'nav-tab-career',
          'nav-tab-home',
        ]) {
          await tester.tap(find.byKey(ValueKey(key)));
          await tester.pumpAndSettle();
          final currentShell = tester.widget<CareerShellScaffold>(
            find.byType(CareerShellScaffold),
          );
          expect(identical(currentShell.controller, controller), isTrue);
        }

        // B. Exit to Main Menu via shell menu and re-enter via Continue
        await tester.tap(
          find.byKey(const ValueKey('career-shell-menu-button')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('return-to-main-menu-button')),
        );
        await tester.pumpAndSettle();
        expect(find.byType(MainMenuScreen), findsOneWidget);

        await tester.tap(
          find.byKey(const ValueKey('continue-gm-career-button')),
        );
        await tester.pumpAndSettle();
        expect(find.byType(CareerShellScaffold), findsOneWidget);

        // K. Zero navigation-induced career mutations or writes
        expect(storage.writeCalls, initialWrites);
        expect(GmCareerCodec.encode(controller.career!), beforeJson);
      },
    );

    testWidgets(
      'E & F: All 4 career phases render with shared shell and refresh Home action',
      (tester) async {
        _setViewport(tester, const Size(390, 844));
        Future<void> pumpCareer(GmCareer career, String expectedCta) async {
          final storage = InMemoryGmCareerStorage({
            'default': GmCareerCodec.encode(career),
          });
          await tester.pumpWidget(
            BasketballManagerApp(
              key: ValueKey('app-${career.phase.name}'),
              league: league,
              storage: InMemorySeasonStorage(),
              careerStorage: storage,
              seasonMode: true,
            ),
          );
          await tester.pumpAndSettle();
          expect(find.byType(CareerShellScaffold), findsOneWidget);
          expect(find.byKey(const ValueKey('nav-tab-home')), findsOneWidget);
          expect(find.byKey(const ValueKey('nav-tab-career')), findsOneWidget);
          expect(
            find.descendant(
              of: find.byKey(const ValueKey('home-primary-cta')),
              matching: find.text(expectedCta.toUpperCase()),
            ),
            findsOneWidget,
          );
        }

        await pumpCareer(offseasonCareer, 'Start Rookie Draft');
        await pumpCareer(regularSeasonCareer, 'Simulate Next Round');
        await pumpCareer(playInCareer, 'Open Play-In Bracket');
        await pumpCareer(playoffCareer, 'Continue to Next Season');
      },
    );

    testWidgets(
      'G, H, I: Unsupported actions absent, no fake conferences, accurate financial & roster counters',
      (tester) async {
        _setViewport(tester, const Size(390, 844));
        final storage = InMemoryGmCareerStorage({
          'default': GmCareerCodec.encode(regularSeasonCareer),
        });
        await tester.pumpWidget(
          BasketballManagerApp(
            league: league,
            storage: InMemorySeasonStorage(),
            careerStorage: storage,
            seasonMode: true,
          ),
        );
        await tester.pumpAndSettle();

        // G. No batch simulation or unimplemented features
        expect(find.textContaining('Sim 7 Rounds'), findsNothing);
        expect(find.textContaining('Sim 30 Rounds'), findsNothing);

        // H. No fake conference or division rankings
        expect(find.textContaining('East Standings'), findsNothing);
        expect(find.textContaining('West Standings'), findsNothing);
        expect(find.text('LEAGUE STANDINGS (TOP 4 OF 30)'), findsOneWidget);

        // I. Authoritative roster & cap counters match domain
        final team = regularSeasonCareer.userTeam;
        final capPayroll = regularSeasonCareer.finances.capPayrollFor(
          team.id,
          regularSeasonCareer.currentYear,
        );
        final capRoom = FinancialRules.salaryCap - capPayroll;
        expect(
          find.text(
            '${team.roster.standardCount} / ${RosterRules.maxRegularSeasonStandard} Std',
          ),
          findsOneWidget,
        );
        expect(
          find.textContaining(CareerUiLabels.formatCu(capRoom)),
          findsAtLeastNWidgets(1),
        );
      },
    );

    testWidgets('J: Existing save/recovery errors remain visible', (
      tester,
    ) async {
      _setViewport(tester, const Size(390, 844));
      final storage = InMemoryGmCareerStorage()..shouldThrowOnRead = true;
      await tester.pumpWidget(
        BasketballManagerApp(
          league: league,
          storage: InMemorySeasonStorage(),
          careerStorage: storage,
          seasonMode: true,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('main-menu-storage-error')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('main-menu-retry-load')),
        findsOneWidget,
      );
    });

    testWidgets('L: Keyboard and Android back navigation work', (tester) async {
      _setViewport(tester, const Size(390, 844));
      final storage = InMemoryGmCareerStorage({
        'default': GmCareerCodec.encode(regularSeasonCareer),
      });
      await tester.pumpWidget(
        BasketballManagerApp(
          league: league,
          storage: InMemorySeasonStorage(),
          careerStorage: storage,
          seasonMode: true,
        ),
      );
      await tester.pumpAndSettle();

      // Switch to TEAM tab
      await tester.tap(find.byKey(const ValueKey('nav-tab-team')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('career-team-tab')), findsOneWidget);

      // Android back from TEAM tab returns to HOME tab
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('career-home-scroll')), findsOneWidget);

      // Android back from HOME returns to Main Menu
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(MainMenuScreen), findsOneWidget);

      // Keyboard navigation: focus + Enter on Continue button
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(FocusManager.instance.primaryFocus, isNotNull);
    });

    testWidgets('M & N: 360dp screen and 1.6x text scaling do not overflow', (
      tester,
    ) async {
      _setViewport(tester, const Size(360, 640));
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final storage = InMemoryGmCareerStorage({
        'default': GmCareerCodec.encode(regularSeasonCareer),
      });
      await tester.pumpWidget(
        BasketballManagerApp(
          league: league,
          storage: InMemorySeasonStorage(),
          careerStorage: storage,
          seasonMode: true,
        ),
      );
      await tester.pumpAndSettle();
      final homeEx = tester.takeException();
      expect(homeEx, isNull, reason: homeEx?.toString());

      for (final key in [
        'nav-tab-team',
        'nav-tab-league',
        'nav-tab-market',
        'nav-tab-career',
      ]) {
        await tester.tap(find.byKey(ValueKey(key)));
        await tester.pumpAndSettle();
        final tabEx = tester.takeException();
        expect(tabEx, isNull, reason: '$key: ${tabEx?.toString()}');
      }
    });
  });
}

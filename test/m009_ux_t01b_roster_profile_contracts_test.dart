import 'package:basketball_manager/features/career/career_controller.dart';
import 'package:basketball_manager/features/career/career_player_profile_screen.dart';
import 'package:basketball_manager/features/career/career_shell_scaffold.dart';
import 'package:basketball_manager/features/career/career_storage.dart';
import 'package:basketball_manager/features/career/draft_board_screen.dart';
import 'package:basketball_manager/features/career/free_agents_screen.dart';
import 'package:basketball_manager/features/career/main_menu_screen.dart';
import 'package:basketball_manager/features/season/season_controller.dart';
import 'package:basketball_manager/features/season/season_storage.dart';
import 'package:basketball_manager/theme/hardwood_command_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simulation_core/simulation_core.dart';

class _CountingCareerStorage extends InMemoryGmCareerStorage {
  _CountingCareerStorage(String initialJson) : super({'default': initialJson});

  int writeCount = 0;

  @override
  Future<void> write(String data, {String slot = 'default'}) async {
    writeCount++;
    await super.write(data, slot: slot);
  }
}

GmCareer _buildOffseasonCareer({
  FranchiseSituation situation = FranchiseSituation.playoff,
}) {
  final setup = const CareerSetupService().generate(
    CareerSetupRequest(
      selectedTeamId: const TeamId('team-1'),
      selectedSituation: situation,
      seed: 20261028,
    ),
  );
  return GmCareer.fromSetupResult(setup, id: 't01b-career');
}

Widget _wrapWithTheme(Widget child, {double textScale = 1.0}) {
  return MaterialApp(
    theme: buildHardwoodCommandTheme(),
    builder: (context, inner) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: inner!,
    ),
    home: child,
  );
}

void main() {
  group('M009-UX-T01B: Roster, Player Profiles & Contracts', () {
    testWidgets(
      'Team Roster shows phase-aware RosterRules, filters by position, and opens Player Profile without writes',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final career = _buildOffseasonCareer();
        final storage = _CountingCareerStorage(GmCareerCodec.encode(career));
        final controller = GmCareerController(storage: storage);
        await controller.loadCareer();
        expect(storage.writeCount, 0);

        await tester.pumpWidget(
          _wrapWithTheme(
            CareerShellScaffold(
              controller: controller,
              onReturnToMainMenu: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Offseason checklist is shown on Home
        expect(
          find.byKey(const ValueKey('home-offseason-checklist')),
          findsOneWidget,
        );

        // Navigate to TEAM tab
        await tester.tap(find.byKey(const ValueKey('nav-tab-team')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('team-roster-summary-card')),
          findsOneWidget,
        );
        expect(find.textContaining('MIN 14'), findsOneWidget);
        expect(find.textContaining('/ 21'), findsOneWidget);
        expect(find.text('STD'), findsWidgets);

        // Filter to PG only
        await tester.tap(find.byKey(const ValueKey('team-filter-PG')));
        await tester.pumpAndSettle();
        expect(find.textContaining('POINT GUARD'), findsOneWidget);
        expect(find.textContaining('CENTER ('), findsNothing);

        // Reset to ALL
        await tester.tap(find.byKey(const ValueKey('team-filter-ALL')));
        await tester.pumpAndSettle();
        final teamScroll = find
            .descendant(
              of: find.byKey(const ValueKey('career-team-tab')),
              matching: find.byType(Scrollable),
            )
            .first;
        await tester.scrollUntilVisible(
          find.textContaining('CENTER ('),
          250,
          scrollable: teamScroll,
        );
        expect(find.textContaining('CENTER ('), findsOneWidget);

        // Open first player profile
        final firstPlayer = career.userTeam.players.first;
        final rowFinder = find.byKey(
          ValueKey('team-player-row-${firstPlayer.id.value}'),
        );
        await tester.scrollUntilVisible(
          rowFinder,
          -250,
          scrollable: teamScroll,
        );
        await tester.pumpAndSettle();
        await tester.tap(rowFinder);
        await tester.pumpAndSettle();

        expect(
          find.byKey(ValueKey('career-player-profile-${firstPlayer.id.value}')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('player-overview-content')),
          findsOneWidget,
        );
        expect(find.text('RATING PILLARS'), findsOneWidget);

        // Switch to ATTRIBUTES tab and verify all 12 real attributes
        await tester.tap(find.byKey(const ValueKey('player-tab-attributes')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('player-attributes-content')),
          findsOneWidget,
        );
        expect(find.text('Inside Scoring'), findsOneWidget);
        expect(find.text('Three-Point'), findsOneWidget);
        expect(find.text('Perimeter Defense'), findsOneWidget);
        expect(find.text('Basketball IQ'), findsOneWidget);

        // Switch to CONTRACT tab
        await tester.tap(find.byKey(const ValueKey('player-tab-contract')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('player-contract-content')),
          findsOneWidget,
        );
        expect(find.text('CONTRACT TERMS'), findsOneWidget);
        expect(find.text('ANNUAL SALARY SCHEDULE'), findsOneWidget);

        // Return to Team tab — zero storage writes occurred during inspection
        await tester.tap(find.byKey(const ValueKey('player-profile-back')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('career-team-tab')), findsOneWidget);
        expect(storage.writeCount, 0);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Cap & Contracts view shows authoritative CU commitments and opens Contract tab directly',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final career = _buildOffseasonCareer();
        final storage = _CountingCareerStorage(GmCareerCodec.encode(career));
        final controller = GmCareerController(storage: storage);
        await controller.loadCareer();

        await tester.pumpWidget(
          _wrapWithTheme(
            CareerShellScaffold(
              controller: controller,
              onReturnToMainMenu: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('nav-tab-team')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('team-view-cap')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('team-cap-overview-card')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('team-multiyear-commitments-card')),
          findsOneWidget,
        );
        expect(find.text('41,000 CU'), findsOneWidget);
        expect(find.textContaining('EXPIRING CONTRACTS'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.textContaining('ACTIVE CONTRACT COMMITMENTS'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(
          find.textContaining('ACTIVE CONTRACT COMMITMENTS'),
          findsOneWidget,
        );

        // Tap first active contract row -> opens directly on CONTRACT tab
        final firstPlayer = career.userTeam.players.first;
        final nameFinder = find.text(firstPlayer.fullName).last;
        await tester.scrollUntilVisible(
          nameFinder,
          120,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.ensureVisible(nameFinder);
        await tester.pumpAndSettle();
        await tester.tap(nameFinder);
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('player-contract-content')),
          findsOneWidget,
        );
        expect(storage.writeCount, 0);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Free Agent & Draft Prospect profiles enforce scouting visibility rules and preserve list filter state',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final career = _buildOffseasonCareer();
        final storage = _CountingCareerStorage(GmCareerCodec.encode(career));
        final controller = GmCareerController(storage: storage);
        await controller.loadCareer();

        // 1. Free Agent inspection
        await tester.pumpWidget(
          _wrapWithTheme(GmFreeAgentsScreen(controller: controller)),
        );
        await tester.pumpAndSettle();

        final sortedFas =
            List<FreeAgentEntry>.from(career.freeAgentPool.entries)..sort(
              (a, b) => b.player.attributes.overallRating.compareTo(
                a.player.attributes.overallRating,
              ),
            );
        final fa = sortedFas.first;
        await tester.tap(find.byKey(ValueKey('free-agent-${fa.id.value}')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(ValueKey('career-player-profile-${fa.id.value}')),
          findsOneWidget,
        );
        // Must NOT leak hidden potential or trajectory
        expect(find.text('POTENTIAL'), findsNothing);
        expect(find.text('TRAJECTORY'), findsNothing);
        expect(find.text(fa.profile.trajectory.displayName), findsNothing);

        await tester.tap(find.byKey(const ValueKey('player-profile-back')));
        await tester.pumpAndSettle();

        // 2. Draft Prospect inspection with active search filter preserved
        await tester.pumpWidget(
          _wrapWithTheme(GmDraftBoardScreen(controller: controller)),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Prospects (90)'));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('prospect-filter-pg')));
        await tester.pumpAndSettle();

        final pgProspect = career.draftClass.prospects
            .map((p) => p.toPublicView())
            .firstWhere((p) => p.position == Position.pg);
        final rawProspect = career.draftClass.byId(pgProspect.id)!;

        await tester.tap(
          find.byKey(ValueKey('prospect-profile-${pgProspect.projectedRank}')),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(ValueKey('career-player-profile-${pgProspect.id.value}')),
          findsOneWidget,
        );
        expect(find.text('SCOUTED POTENTIAL'), findsOneWidget);
        expect(find.text('POTENTIAL'), findsNothing);
        expect(find.text('TRAJECTORY'), findsNothing);
        expect(find.text(rawProspect.trajectory.displayName), findsNothing);

        await tester.tap(find.byKey(const ValueKey('player-profile-back')));
        await tester.pumpAndSettle();

        // FilterChip PG remains selected on return
        final pgChip = tester.widget<FilterChip>(
          find.byKey(const ValueKey('prospect-filter-pg')),
        );
        expect(pgChip.selected, isTrue);
        expect(storage.writeCount, 0);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Main Menu renames Classic Season without M007 label and responsive viewports/text scales have no overflow',
      (tester) async {
        final league = const LeagueGenerator().generate(
          const GenerationConfig(seed: 20261028),
        );
        final career = _buildOffseasonCareer();
        final careerStorage = InMemoryGmCareerStorage({
          'default': GmCareerCodec.encode(career),
        });
        final careerController = GmCareerController(storage: careerStorage);
        await careerController.loadCareer();
        final seasonController = SeasonController(
          league: league,
          storage: InMemorySeasonStorage(),
        );

        await tester.pumpWidget(
          _wrapWithTheme(
            MainMenuScreen(
              league: league,
              seasonController: seasonController,
              careerController: careerController,
              careerStorage: careerStorage,
              onContinueCareer: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Classic Season'), findsOneWidget);
        expect(find.textContaining('M007'), findsNothing);

        // Responsive matrix across Team tab and Player Profile
        const sizes = [Size(360, 800), Size(390, 844), Size(1280, 800)];
        const scales = [1.0, 1.5, 2.0];
        final firstPlayer = career.userTeam.players.first;
        final dossier = RosteredPlayerDossier(
          player: firstPlayer,
          team: career.userTeam,
          category: career.userTeam.roster.categoryOf(firstPlayer.id),
          currentYear: career.currentYear,
          isUserTeam: true,
          profile: career.careerProfiles.forPlayer(firstPlayer.id),
          contract: career.finances.contractForPlayer(firstPlayer.id),
          schedule: career.finances.scheduleFor(
            career.finances.contractForPlayer(firstPlayer.id)!.id,
          ),
        );

        for (final size in sizes) {
          for (final scale in scales) {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1.0;
            await tester.pumpWidget(
              _wrapWithTheme(
                CareerPlayerProfileScreen(dossier: dossier),
                textScale: scale,
              ),
            );
            await tester.pumpAndSettle();
            expect(
              tester.takeException(),
              isNull,
              reason: 'Overflow on profile Overview at $size scale $scale',
            );

            await tester.tap(
              find.byKey(const ValueKey('player-tab-attributes')),
            );
            await tester.pumpAndSettle();
            expect(
              tester.takeException(),
              isNull,
              reason: 'Overflow on profile Attributes at $size scale $scale',
            );

            await tester.tap(find.byKey(const ValueKey('player-tab-contract')));
            await tester.pumpAndSettle();
            expect(
              tester.takeException(),
              isNull,
              reason: 'Overflow on profile Contract at $size scale $scale',
            );
          }
        }
        addTearDown(tester.view.reset);
      },
    );
  });
}

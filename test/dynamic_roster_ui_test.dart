import 'package:basketball_manager/features/career/career_controller.dart';
import 'package:basketball_manager/features/career/career_storage.dart';
import 'package:basketball_manager/features/career/offseason_overview_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simulation_core/simulation_core.dart';

import 'support/financial_fixtures.dart';

void _useSmallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  const service = CareerSetupService();
  const seed = 20261028;

  Player createTestPlayer(String id, {Position position = Position.pg}) {
    return Player(
      id: PlayerId(id),
      firstName: 'Added',
      lastName: id,
      position: position,
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
  }

  PlayerCareerProfile createTestProfile(Player player) {
    return PlayerCareerProfile(
      playerId: player.id,
      age: 21,
      potential: 70,
      trajectory: DevelopmentTrajectory.steady,
    );
  }

  group('M008-T05R: Dynamic Roster UI Presentation', () {
    testWidgets(
      'Displays initial 12-player roster composition breakdown at 360x640 without overflow',
      (tester) async {
        _useSmallViewport(tester);

        final setup = service.generate(
          const CareerSetupRequest(
            selectedTeamId: TeamId('team-1'),
            selectedSituation: FranchiseSituation.tanking,
            seed: seed,
          ),
        );
        final career = GmCareer.fromSetupResult(setup);
        final controller = GmCareerController(
          storage: InMemoryGmCareerStorage({
            'default': GmCareerCodec.encode(career),
          }),
        );
        await controller.loadCareer();
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          MaterialApp(home: GmOffseasonOverviewScreen(controller: controller)),
        );
        await tester.pumpAndSettle();

        // Header shows franchise and current roster count
        expect(find.text('Current Roster (12 Players)'), findsOneWidget);

        // Composition header is displayed
        expect(
          find.byKey(const ValueKey('card-roster-composition')),
          findsOneWidget,
        );
        expect(find.text('Total: 12/21'), findsOneWidget);
        expect(
          find.textContaining('Standard: 12/15 • Two-Way: 0/3 • Camp: 0'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Reflects expanded roster composition (15 standard, 2 two-way, 1 camp) at 360x640',
      (tester) async {
        _useSmallViewport(tester);

        final setup = service.generate(
          const CareerSetupRequest(
            selectedTeamId: TeamId('team-1'),
            selectedSituation: FranchiseSituation.tanking,
            seed: seed,
          ),
        );
        final career = GmCareer.fromSetupResult(setup);

        // Expand user roster: 15 standard, 2 two-way, 1 camp (18 total)
        var expandedRoster = career.userTeam.roster
            .withPlayer(
              createTestPlayer('std-13'),
              category: RosterCategory.standard,
            )
            .withPlayer(
              createTestPlayer('std-14'),
              category: RosterCategory.standard,
            )
            .withPlayer(
              createTestPlayer('std-15'),
              category: RosterCategory.standard,
            )
            .withPlayer(
              createTestPlayer('tw-1'),
              category: RosterCategory.twoWay,
            )
            .withPlayer(
              createTestPlayer('tw-2'),
              category: RosterCategory.twoWay,
            )
            .withPlayer(
              createTestPlayer('tc-1'),
              category: RosterCategory.trainingCamp,
            );

        final updatedTeam = career.userTeam.copyWith(roster: expandedRoster);
        final updatedProfiles = Map<String, PlayerCareerProfile>.from(
          career.careerProfiles.profiles,
        );
        for (final p in expandedRoster.players.skip(12)) {
          updatedProfiles[p.id.value] = createTestProfile(p);
        }
        final updatedCareer = withBootstrappedTeam(
          career,
          updatedTeam,
          careerProfiles: LeagueCareerProfiles(
            leagueSeed: career.generationSeed,
            profiles: updatedProfiles,
          ),
        );
        final controller = GmCareerController(
          storage: InMemoryGmCareerStorage({
            'default': GmCareerCodec.encode(updatedCareer),
          }),
        );
        await controller.loadCareer();
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          MaterialApp(home: GmOffseasonOverviewScreen(controller: controller)),
        );
        await tester.pumpAndSettle();

        expect(find.text('Current Roster (18 Players)'), findsOneWidget);
        expect(find.text('Total: 18/21'), findsOneWidget);
        expect(
          find.textContaining('Standard: 15/15 • Two-Way: 2/3 • Camp: 1'),
          findsOneWidget,
        );
      },
    );
  });
}

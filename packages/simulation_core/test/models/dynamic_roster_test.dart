import 'dart:convert';

import 'package:simulation_core/simulation_core.dart';
import 'package:test/test.dart';

import '../support/financial_fixtures.dart';

void main() {
  const service = CareerSetupService();
  const seed = 20261028;

  Player createTestPlayer(String id, {Position position = Position.pg}) {
    return Player(
      id: PlayerId(id),
      firstName: 'Test',
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
      age: 22,
      potential: 75,
      trajectory: DevelopmentTrajectory.steady,
    );
  }

  group('M008-T05R: Dynamic Roster Architecture Foundation', () {
    late CareerSetupResult setup;
    late GmCareer career;

    setUpAll(() {
      setup = service.generate(
        const CareerSetupRequest(
          selectedTeamId: TeamId('team-1'),
          selectedSituation: FranchiseSituation.tanking,
          seed: seed,
        ),
      );
      career = GmCareer.fromSetupResult(setup);
    });

    test(
      '1 & 2. Initial generation creates 30 teams, 12 players per team, 360 players',
      () {
        expect(career.league.teams.length, 30);
        for (final team in career.league.teams) {
          expect(team.roster.players.length, 12);
          expect(team.roster.standardCount, 12);
          expect(team.roster.twoWayCount, 0);
          expect(team.roster.trainingCampCount, 0);
          expect(team.roster.totalContractedCount, 12);
        }
        expect(career.careerProfiles.length, 360);
      },
    );

    test('3. Opening Offseason accepts 12-player standard rosters', () {
      final userTeam = career.userTeam;
      final result = userTeam.roster.validateStructure(
        phase: CareerPhase.openingOffseason,
      );
      expect(result.isValid, isTrue);
      expect(() => career.validate(), returnsNormally);
    });

    test(
      '4 & 5. A franchise can validly expand up to 15 standard players in offseason',
      () {
        var roster = career.userTeam.roster;

        // Add 3 more standard players (total 15)
        for (var i = 13; i <= 15; i++) {
          final p = createTestPlayer('extra-std-$i');
          roster = roster.withPlayer(p, category: RosterCategory.standard);
        }

        expect(roster.players.length, 15);
        expect(roster.standardCount, 15);
        expect(roster.twoWayCount, 0);
        expect(roster.trainingCampCount, 0);

        final val = roster.validateStructure(
          phase: CareerPhase.openingOffseason,
        );
        expect(val.isValid, isTrue);
      },
    );

    test('6. A 16th standard player is rejected by structural validation', () {
      var roster = career.userTeam.roster;
      for (var i = 13; i <= 16; i++) {
        final p = createTestPlayer('extra-std-$i');
        roster = roster.withPlayer(p, category: RosterCategory.standard);
      }

      expect(roster.standardCount, 16);
      final val = roster.validateStructure(phase: CareerPhase.openingOffseason);
      expect(val.isValid, isFalse);
      expect(val.issues.first, contains('exceeds offseason limit (15)'));
      expect(() => val.throwIfInvalid(), throwsA(isA<FormatException>()));
    });

    test(
      '7. Up to 3 two-way players are allowed and do not count against 15 standard spots',
      () {
        var roster = career.userTeam.roster;
        // 15 standard players
        for (var i = 13; i <= 15; i++) {
          final p = createTestPlayer('extra-std-$i');
          roster = roster.withPlayer(p, category: RosterCategory.standard);
        }
        // 3 two-way players
        for (var i = 1; i <= 3; i++) {
          final p = createTestPlayer('two-way-$i');
          roster = roster.withPlayer(p, category: RosterCategory.twoWay);
        }

        expect(roster.standardCount, 15);
        expect(roster.twoWayCount, 3);
        expect(roster.totalContractedCount, 18);

        final val = roster.validateStructure(
          phase: CareerPhase.openingOffseason,
        );
        expect(val.isValid, isTrue);
      },
    );

    test('8. A 4th two-way player is rejected by structural validation', () {
      var roster = career.userTeam.roster;
      for (var i = 1; i <= 4; i++) {
        final p = createTestPlayer('two-way-$i');
        roster = roster.withPlayer(p, category: RosterCategory.twoWay);
      }

      expect(roster.twoWayCount, 4);
      final val = roster.validateStructure(phase: CareerPhase.openingOffseason);
      expect(val.isValid, isFalse);
      expect(val.issues.first, contains('exceeds limit (3)'));
    });

    test(
      '9. A 21-player offseason roster is valid with compliant category counts',
      () {
        var roster = career.userTeam.roster;
        // 15 standard
        for (var i = 13; i <= 15; i++) {
          final p = createTestPlayer('extra-std-$i');
          roster = roster.withPlayer(p, category: RosterCategory.standard);
        }
        // 3 two-way
        for (var i = 1; i <= 3; i++) {
          final p = createTestPlayer('two-way-$i');
          roster = roster.withPlayer(p, category: RosterCategory.twoWay);
        }
        // 3 training camp (total 21)
        for (var i = 1; i <= 3; i++) {
          final p = createTestPlayer('camp-$i');
          roster = roster.withPlayer(p, category: RosterCategory.trainingCamp);
        }

        expect(roster.standardCount, 15);
        expect(roster.twoWayCount, 3);
        expect(roster.trainingCampCount, 3);
        expect(roster.totalContractedCount, 21);

        final val = roster.validateStructure(
          phase: CareerPhase.openingOffseason,
        );
        expect(val.isValid, isTrue);
      },
    );

    test('10. A 22-player offseason roster is rejected', () {
      var roster = career.userTeam.roster;
      // 15 standard
      for (var i = 13; i <= 15; i++) {
        final p = createTestPlayer('extra-std-$i');
        roster = roster.withPlayer(p, category: RosterCategory.standard);
      }
      // 3 two-way
      for (var i = 1; i <= 3; i++) {
        final p = createTestPlayer('two-way-$i');
        roster = roster.withPlayer(p, category: RosterCategory.twoWay);
      }
      // 4 training camp (total 22)
      for (var i = 1; i <= 4; i++) {
        final p = createTestPlayer('camp-$i');
        roster = roster.withPlayer(p, category: RosterCategory.trainingCamp);
      }

      expect(roster.totalContractedCount, 22);
      final val = roster.validateStructure(phase: CareerPhase.openingOffseason);
      expect(val.isValid, isFalse);
      expect(val.issues.first, contains('exceeds offseason limit (21)'));
    });

    test('11. Regular-season readiness fails if standard count < 14', () {
      final roster12 = career.userTeam.roster;
      expect(roster12.standardCount, 12);

      // Structurally valid in opening offseason
      expect(
        roster12.validateStructure(phase: CareerPhase.openingOffseason).isValid,
        isTrue,
      );

      // But fails regular-season readiness check
      final readyCheck = roster12.validateRegularSeasonReadiness();
      expect(readyCheck.isValid, isFalse);
      expect(readyCheck.issues.first, contains('requires at least 14'));

      // Add 2 standard players (total 14) -> passes regular season readiness
      final roster14 = roster12
          .withPlayer(
            createTestPlayer('std-13'),
            category: RosterCategory.standard,
          )
          .withPlayer(
            createTestPlayer('std-14'),
            category: RosterCategory.standard,
          );

      expect(roster14.validateRegularSeasonReadiness().isValid, isTrue);
    });

    test('12. Training-camp players prevent regular-season readiness', () {
      // 14 standard + 1 training camp
      final roster = career.userTeam.roster
          .withPlayer(
            createTestPlayer('std-13'),
            category: RosterCategory.standard,
          )
          .withPlayer(
            createTestPlayer('std-14'),
            category: RosterCategory.standard,
          )
          .withPlayer(
            createTestPlayer('camp-1'),
            category: RosterCategory.trainingCamp,
          );

      final readyCheck = roster.validateRegularSeasonReadiness();
      expect(readyCheck.isValid, isFalse);
      expect(
        readyCheck.issues.first,
        contains('training-camp players; all must be converted or waived'),
      );
    });

    test('13. Duplicate membership across players is rejected by Roster', () {
      final player = career.userTeam.players.first;
      expect(
        () => career.userTeam.roster.withPlayer(player),
        throwsA(isA<DomainValidationException>()),
      );
    });

    test(
      '14 & 15. Draft rights and free agents exist outside franchise roster counts',
      () {
        expect(career.draftClass.length, 90);
        final draftProspect = career.draftClass.rankedFirst;

        // Draft prospect is not in any team roster
        for (final team in career.league.teams) {
          expect(team.players.any((p) => p.id == draftProspect.id), isFalse);
        }

        // An uncontracted free agent has no team roster membership
        final freeAgent = createTestPlayer('unassigned-fa');
        for (final team in career.league.teams) {
          expect(team.players.any((p) => p.id == freeAgent.id), isFalse);
        }
      },
    );

    test(
      '16. Existing player identities, attributes, and profiles remain intact',
      () {
        final p0 = career.userTeam.players.first;
        expect(p0.id.value, 'player-1-1');
        expect(p0.fullName, isNotEmpty);
        expect(p0.attributes.overallRating, inInclusiveRange(40, 99));

        final profile = career.careerProfiles.forPlayer(p0.id);
        expect(profile, isNotNull);
        expect(profile!.age, inInclusiveRange(19, 38));
        expect(
          profile.potential,
          greaterThanOrEqualTo(p0.attributes.overallRating),
        );
      },
    );

    test(
      '17. Schema v1 and v2 migrations decode cleanly and synthesize standard roster memberships',
      () {
        final jsonV3 =
            jsonDecode(GmCareerCodec.encode(career)) as Map<String, dynamic>;

        // Simulate v1
        final v1Map = Map<String, dynamic>.from(jsonV3)
          ..['schemaVersion'] = 1
          ..remove('draftOrder')
          ..remove('draftClass')
          ..remove('rosterMemberships');
        final decodedV1 = GmCareerCodec.decode(jsonEncode(v1Map));
        expect(decodedV1.schemaVersion, GmCareer.currentSchemaVersion);
        expect(decodedV1.userTeam.roster.standardCount, 12);
        expect(decodedV1.userTeam.roster.twoWayCount, 0);

        // Simulate v2
        final v2Map = Map<String, dynamic>.from(jsonV3)
          ..['schemaVersion'] = 2
          ..remove('rosterMemberships');
        final decodedV2 = GmCareerCodec.decode(jsonEncode(v2Map));
        expect(decodedV2.schemaVersion, GmCareer.currentSchemaVersion);
        expect(decodedV2.userTeam.roster.standardCount, 12);
        expect(decodedV2.userTeam.roster.twoWayCount, 0);
      },
    );

    test(
      '18. Save/load preserves expanded roster memberships and categories',
      () {
        // Build career with user team having 14 standard + 2 two-way + 1 camp (17 players)
        var expandedRoster = career.userTeam.roster
            .withPlayer(
              createTestPlayer('exp-std-13'),
              category: RosterCategory.standard,
            )
            .withPlayer(
              createTestPlayer('exp-std-14'),
              category: RosterCategory.standard,
            )
            .withPlayer(
              createTestPlayer('exp-tw-1'),
              category: RosterCategory.twoWay,
            )
            .withPlayer(
              createTestPlayer('exp-tw-2'),
              category: RosterCategory.twoWay,
            )
            .withPlayer(
              createTestPlayer('exp-tc-1'),
              category: RosterCategory.trainingCamp,
            );

        final updatedUserTeam = career.userTeam.copyWith(
          roster: expandedRoster,
        );

        // Add profiles for the 5 new players
        final updatedProfiles = Map<String, PlayerCareerProfile>.from(
          career.careerProfiles.profiles,
        );
        for (final p in expandedRoster.players.skip(12)) {
          updatedProfiles[p.id.value] = createTestProfile(p);
        }
        final newLeagueCareerProfiles = LeagueCareerProfiles(
          leagueSeed: career.generationSeed,
          profiles: updatedProfiles,
        );

        final expandedCareer = withBootstrappedTeam(
          career,
          updatedUserTeam,
          careerProfiles: newLeagueCareerProfiles,
        );

        final encoded = GmCareerCodec.encode(expandedCareer);
        final decoded = GmCareerCodec.decode(encoded);

        final decodedUserTeam = decoded.userTeam;
        expect(decodedUserTeam.roster.players.length, 17);
        expect(decodedUserTeam.roster.standardCount, 14);
        expect(decodedUserTeam.roster.twoWayCount, 2);
        expect(decodedUserTeam.roster.trainingCampCount, 1);
        expect(
          decodedUserTeam.roster.categoryOf(const PlayerId('exp-tw-1')),
          RosterCategory.twoWay,
        );
        expect(
          decodedUserTeam.roster.categoryOf(const PlayerId('exp-tc-1')),
          RosterCategory.trainingCamp,
        );
        expect(
          decodedUserTeam.roster.categoryOf(const PlayerId('exp-std-13')),
          RosterCategory.standard,
        );
      },
    );

    test(
      'Simulation compatibility: expandPreset operates cleanly on expanded 18-player roster',
      () {
        // Expand team roster to 18 players
        var roster = career.userTeam.roster;
        for (var i = 13; i <= 15; i++) {
          roster = roster.withPlayer(
            createTestPlayer('extra-$i'),
            category: RosterCategory.standard,
          );
        }
        for (var i = 1; i <= 3; i++) {
          roster = roster.withPlayer(
            createTestPlayer('extra-tw-$i'),
            category: RosterCategory.twoWay,
          );
        }
        final expandedTeam = career.userTeam.copyWith(roster: roster);

        final lineup = CourtLineup.defaultFor(expandedTeam);
        final rules = GameRules();

        final expandedTargets = RotationPlan.expandPreset(
          preset: RotationPreset.balanced,
          team: expandedTeam,
          lineup: lineup,
          rules: rules,
        );

        // All 18 players receive targets (active rotation receives minutes, deep bench receives 0)
        expect(expandedTargets.length, 18);
        final totalSeconds = expandedTargets.values.fold(0, (a, b) => a + b);
        expect(totalSeconds, RotationPlan.regulationTeamTotal(rules));

        // Inactive bench players receive 0 seconds cleanly without exception
        final zeroes = expandedTargets.values.where((s) => s == 0);
        expect(zeroes.length, greaterThanOrEqualTo(9));
      },
    );
  });
}

import 'dart:convert';

import 'package:simulation_core/simulation_core.dart';
import 'package:test/test.dart';

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
      age: 22,
      potential: 75,
      trajectory: DevelopmentTrajectory.steady,
    );
  }

  group('M008-T05R-P1: Roster Persistence Integrity', () {
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
      '1. Exact v3 roster-category round-trip preserves standard, two-way, and training camp',
      () {
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

        final updatedTeam = career.userTeam.copyWith(roster: expandedRoster);
        final updatedProfiles = Map<String, PlayerCareerProfile>.from(
          career.careerProfiles.profiles,
        );
        for (final p in expandedRoster.players.skip(12)) {
          updatedProfiles[p.id.value] = createTestProfile(p);
        }

        final careerV3 = career.withUpdatedTeam(
          updatedTeam,
          careerProfiles: LeagueCareerProfiles(
            leagueSeed: career.generationSeed,
            profiles: updatedProfiles,
          ),
        );

        final encoded = GmCareerCodec.encode(careerV3);
        final decoded = GmCareerCodec.decode(encoded);

        expect(decoded.schemaVersion, GmCareer.currentSchemaVersion);
        final decodedTeam = decoded.userTeam;
        expect(decodedTeam.roster.totalContractedCount, 17);
        expect(decodedTeam.roster.standardCount, 14);
        expect(decodedTeam.roster.twoWayCount, 2);
        expect(decodedTeam.roster.trainingCampCount, 1);
        expect(
          decodedTeam.roster.categoryOf(const PlayerId('exp-std-13')),
          RosterCategory.standard,
        );
        expect(
          decodedTeam.roster.categoryOf(const PlayerId('exp-tw-1')),
          RosterCategory.twoWay,
        );
        expect(
          decodedTeam.roster.categoryOf(const PlayerId('exp-tc-1')),
          RosterCategory.trainingCamp,
        );
      },
    );

    test('2. Missing v3 membership metadata is strictly rejected', () {
      final jsonMap =
          jsonDecode(GmCareerCodec.encode(career)) as Map<String, dynamic>;
      jsonMap.remove('rosterMemberships');

      expect(
        () => GmCareerCodec.decode(jsonEncode(jsonMap)),
        throwsA(
          predicate<FormatException>(
            (e) => e.message.contains(
              'Missing or invalid rosterMemberships in career JSON v3',
            ),
          ),
        ),
      );
    });

    test(
      '3. Missing membership entry for an existing player is strictly rejected',
      () {
        final jsonMap =
            jsonDecode(GmCareerCodec.encode(career)) as Map<String, dynamic>;
        final memberships =
            jsonMap['rosterMemberships'] as Map<String, dynamic>;
        final team1Members = List<dynamic>.from(memberships['team-1'] as List);

        // Remove the last player's membership entry
        final removed = team1Members.removeLast() as Map<String, dynamic>;
        final missingPid = removed['playerId'];
        memberships['team-1'] = team1Members;

        expect(
          () => GmCareerCodec.decode(jsonEncode(jsonMap)),
          throwsA(
            predicate<FormatException>(
              (e) => e.message.contains(
                'Missing roster membership entry for player $missingPid in franchise team-1',
              ),
            ),
          ),
        );
      },
    );

    test(
      '4. Missing membership entry for an entire franchise is strictly rejected',
      () {
        final jsonMap =
            jsonDecode(GmCareerCodec.encode(career)) as Map<String, dynamic>;
        final memberships =
            jsonMap['rosterMemberships'] as Map<String, dynamic>;
        memberships.remove('team-30');

        expect(
          () => GmCareerCodec.decode(jsonEncode(jsonMap)),
          throwsA(
            predicate<FormatException>(
              (e) => e.message.contains(
                'Missing rosterMemberships entry for franchise team-30',
              ),
            ),
          ),
        );
      },
    );

    test(
      '5. Duplicate membership entries for a player are strictly rejected',
      () {
        final jsonMap =
            jsonDecode(GmCareerCodec.encode(career)) as Map<String, dynamic>;
        final memberships =
            jsonMap['rosterMemberships'] as Map<String, dynamic>;
        final team1Members = List<dynamic>.from(memberships['team-1'] as List);

        // Duplicate the first player entry
        team1Members.add(team1Members.first);
        memberships['team-1'] = team1Members;

        expect(
          () => GmCareerCodec.decode(jsonEncode(jsonMap)),
          throwsA(
            predicate<FormatException>(
              (e) => e.message.contains(
                'Duplicate roster membership entry for player',
              ),
            ),
          ),
        );
      },
    );

    test(
      '6. Membership entries referencing nonexistent players are strictly rejected',
      () {
        final jsonMap =
            jsonDecode(GmCareerCodec.encode(career)) as Map<String, dynamic>;
        final memberships =
            jsonMap['rosterMemberships'] as Map<String, dynamic>;
        final team1Members = List<dynamic>.from(memberships['team-1'] as List);

        team1Members.add({
          'playerId': 'player-nonexistent-99',
          'category': 'standard',
        });
        memberships['team-1'] = team1Members;

        expect(
          () => GmCareerCodec.decode(jsonEncode(jsonMap)),
          throwsA(
            predicate<FormatException>(
              (e) => e.message.contains('does not belong to franchise team-1'),
            ),
          ),
        );
      },
    );

    test(
      '7. Membership entries referencing nonexistent franchises are strictly rejected',
      () {
        final jsonMap =
            jsonDecode(GmCareerCodec.encode(career)) as Map<String, dynamic>;
        final memberships =
            jsonMap['rosterMemberships'] as Map<String, dynamic>;
        memberships['team-fake-99'] = [];

        expect(
          () => GmCareerCodec.decode(jsonEncode(jsonMap)),
          throwsA(
            predicate<FormatException>(
              (e) => e.message.contains(
                'Unknown franchise team-fake-99 in rosterMemberships',
              ),
            ),
          ),
        );
      },
    );

    test(
      '8. Conflicting redundant category representations are strictly rejected',
      () {
        // Create a save where user team has player-1-1 as standard in rosterMemberships
        // but inline league.teams[0].roster.categories has player-1-1 as twoWay
        final jsonMap =
            jsonDecode(GmCareerCodec.encode(career)) as Map<String, dynamic>;
        final rawLeague = jsonMap['league'] as Map<String, dynamic>;
        final rawTeams = rawLeague['teams'] as List<dynamic>;
        final rawTeam1 = rawTeams.first as Map<String, dynamic>;
        final rawRoster = rawTeam1['roster'] as Map<String, dynamic>;

        // Inject conflicting inline category
        rawRoster['categories'] = {'player-1-1': 'twoWay'};

        expect(
          () => GmCareerCodec.decode(jsonEncode(jsonMap)),
          throwsA(
            predicate<FormatException>(
              (e) => e.message.contains(
                'Conflicting roster categories for player player-1-1 on franchise team-1',
              ),
            ),
          ),
        );
      },
    );

    test(
      '9. Realistic v1 and v2 legacy save migration preserves career and derives standard memberships',
      () {
        final jsonV3 =
            jsonDecode(GmCareerCodec.encode(career)) as Map<String, dynamic>;

        // Simulate legacy v1 save
        final v1Map = Map<String, dynamic>.from(jsonV3)
          ..['schemaVersion'] = 1
          ..remove('draftOrder')
          ..remove('draftClass')
          ..remove('rosterMemberships');

        final decodedV1 = GmCareerCodec.decode(jsonEncode(v1Map));
        expect(decodedV1.schemaVersion, GmCareer.currentSchemaVersion);
        expect(decodedV1.league.teams.length, 30);
        for (final t in decodedV1.league.teams) {
          expect(t.roster.standardCount, 12);
          expect(t.roster.twoWayCount, 0);
          expect(t.roster.trainingCampCount, 0);
        }
        expect(decodedV1.draftOrder.totalPicks, 60);
        expect(decodedV1.draftClass.length, 90);

        // Simulate legacy v2 save
        final v2Map = Map<String, dynamic>.from(jsonV3)
          ..['schemaVersion'] = 2
          ..remove('rosterMemberships');

        final decodedV2 = GmCareerCodec.decode(jsonEncode(v2Map));
        expect(decodedV2.schemaVersion, GmCareer.currentSchemaVersion);
        expect(decodedV2.league.teams.length, 30);
        for (final t in decodedV2.league.teams) {
          expect(t.roster.standardCount, 12);
          expect(t.roster.twoWayCount, 0);
        }
      },
    );

    test(
      '10. Preservation of all player identities and profiles across migration',
      () {
        final jsonV3 =
            jsonDecode(GmCareerCodec.encode(career)) as Map<String, dynamic>;
        final v2Map = Map<String, dynamic>.from(jsonV3)
          ..['schemaVersion'] = 2
          ..remove('rosterMemberships');

        final migrated = GmCareerCodec.decode(jsonEncode(v2Map));

        for (var t = 0; t < 30; t++) {
          final origT = career.league.teams[t];
          final migT = migrated.league.teams[t];
          expect(migT.id, origT.id);
          expect(migT.players.length, origT.players.length);

          for (var p = 0; p < origT.players.length; p++) {
            final origP = origT.players[p];
            final migP = migT.players[p];
            expect(migP.id, origP.id);
            expect(migP.fullName, origP.fullName);
            expect(migP.position, origP.position);
            expect(migP.attributes.asMap, origP.attributes.asMap);

            final origProf = career.careerProfiles.forPlayer(origP.id);
            final migProf = migrated.careerProfiles.forPlayer(migP.id);
            expect(migProf!.age, origProf!.age);
            expect(migProf.potential, origProf.potential);
            expect(migProf.trajectory, origProf.trajectory);
          }
        }
      },
    );

    test(
      '11. Non-destructive rejection of malformed data preserves input string',
      () {
        const corruptJson =
            '{"schemaVersion":3,"id":"career-corrupted","league":{}}';
        expect(
          () => GmCareerCodec.decode(corruptJson),
          throwsA(isA<FormatException>()),
        );
        // Input string is untouched
        expect(corruptJson, contains('career-corrupted'));
      },
    );

    test(
      '12. Existing regular-season readiness rules remain strictly enforced',
      () {
        final roster12 = career.userTeam.roster;
        // 12 standard players fail regular-season readiness
        final check12 = roster12.validateRegularSeasonReadiness();
        expect(check12.isValid, isFalse);
        expect(check12.issues.first, contains('requires at least 14'));

        // 14 standard players pass
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

        // 14 standard + 1 training camp fails
        final rosterCamp = roster14.withPlayer(
          createTestPlayer('tc-1'),
          category: RosterCategory.trainingCamp,
        );
        final checkCamp = rosterCamp.validateRegularSeasonReadiness();
        expect(checkCamp.isValid, isFalse);
        expect(
          checkCamp.issues.first,
          contains('training-camp players; all must be converted or waived'),
        );
      },
    );
  });
}

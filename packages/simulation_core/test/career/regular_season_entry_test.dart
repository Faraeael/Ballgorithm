import 'dart:convert';

import 'package:simulation_core/simulation_core.dart';
import 'package:test/test.dart';

GmCareer _career() => GmCareer.fromSetupResult(
  const CareerSetupService().generate(
    const CareerSetupRequest(
      selectedTeamId: TeamId('team-1'),
      selectedSituation: FranchiseSituation.tanking,
      seed: 20261028,
    ),
  ),
  id: 'season-entry-test',
);

RegularSeasonState _state(GmCareer career) => RegularSeasonState(
  seasonId: RegularSeasonState.seasonIdFor(career.id, career.currentYear),
  seasonYear: career.currentYear,
  scheduleSeed: career.generationSeed,
  openingTeams: [
    for (final team in career.league.teams)
      RegularSeasonTeamIdentity.fromTeam(team),
  ],
  gameResults: const {},
);

void main() {
  group('regular-season entry', () {
    test('incomplete offseason is rejected without changing career', () {
      final career = _career();
      final before = GmCareerCodec.encode(career);

      expect(
        () => const RegularSeasonEntryService().start(career),
        throwsA(isA<RegularSeasonEntryBlocked>()),
      );

      expect(GmCareerCodec.encode(career), before);
      expect(career.phase, CareerPhase.openingOffseason);
      expect(career.regularSeasonState, isNull);
    });

    test('v14 saves migrate without starting a season', () {
      final career = _career();
      final v14 =
          Map<String, dynamic>.from(
              jsonDecode(GmCareerCodec.encode(career)) as Map<String, dynamic>,
            )
            ..['schemaVersion'] = 14
            ..remove('regularSeasonState');

      final migrated = GmCareerCodec.decode(jsonEncode(v14));
      final encoded =
          jsonDecode(GmCareerCodec.encode(migrated)) as Map<String, dynamic>;

      expect(migrated.schemaVersion, GmCareer.currentSchemaVersion);
      expect(migrated.phase, CareerPhase.openingOffseason);
      expect(migrated.regularSeasonState, isNull);
      expect(encoded['regularSeasonState'], isNull);
      expect(
        migrated.league.teams.map((team) => team.id).toList(),
        career.league.teams.map((team) => team.id).toList(),
      );
      expect(
        migrated.finances.contracts.keys.toSet(),
        career.finances.contracts.keys.toSet(),
      );
    });
    test('v17 saves migrate without starting a season', () {
      final career = _career();
      final v17 = Map<String, dynamic>.from(
        jsonDecode(GmCareerCodec.encode(career)) as Map<String, dynamic>,
      )..['schemaVersion'] = 17;

      final migrated = GmCareerCodec.decode(jsonEncode(v17));

      expect(migrated.schemaVersion, GmCareer.currentSchemaVersion);
      expect(migrated.phase, CareerPhase.openingOffseason);
      expect(migrated.regularSeasonState, isNull);
      expect(
        migrated.finances.contracts.keys.toSet(),
        career.finances.contracts.keys.toSet(),
      );
    });

    test('v15 requires state key and rejects impossible phase-state pairs', () {
      final career = _career();
      final base =
          jsonDecode(GmCareerCodec.encode(career)) as Map<String, dynamic>;
      final missing = Map<String, dynamic>.from(base)
        ..remove('regularSeasonState');
      expect(
        () => GmCareerCodec.decode(jsonEncode(missing)),
        throwsFormatException,
      );

      final mismatched = Map<String, dynamic>.from(base)
        ..['phase'] = CareerPhase.regularSeason.jsonValue;
      expect(
        () => GmCareerCodec.decode(jsonEncode(mismatched)),
        throwsFormatException,
      );

      final unready = career.copyWith(
        phase: CareerPhase.regularSeason,
        regularSeasonState: _state(career),
      );
      final forgedNative = Map<String, dynamic>.from(base)
        ..['phase'] = CareerPhase.regularSeason.jsonValue
        ..['regularSeasonState'] = _state(career).toJson();
      expect(() => GmCareerCodec.encode(unready), throwsFormatException);
      expect(
        () => GmCareerCodec.decode(jsonEncode(forgedNative)),
        throwsFormatException,
      );
    });

    test('entry state rejects prior game results and seed drift', () {
      final career = _career();
      expect(
        () => RegularSeasonState(
          seasonId: RegularSeasonState.seasonIdFor(
            career.id,
            career.currentYear,
          ),
          seasonYear: career.currentYear,
          scheduleSeed: career.generationSeed,
          openingTeams: [
            for (final team in career.league.teams)
              RegularSeasonTeamIdentity.fromTeam(team),
          ],
          gameResults: {
            'game-1': RegularSeasonGameResult(
              fixtureId: 'game-1',
              seasonId: RegularSeasonState.seasonIdFor(
                career.id,
                career.currentYear,
              ),
              seasonYear: career.currentYear,
              homeTeamId: career.league.teams.first.id,
              awayTeamId: career.league.teams[1].id,
              gameSeed: 1,
              inputFingerprint: 'fake',
              simulationVersion: 7,
              rulesVersion: 3,
              eventSchemaVersion: 3,
              prngImplementationId: 'xorshift32-v1',
              periodsPlayed: 4,
              summary: SeasonGameSummary(
                homeScore: 0,
                awayScore: 0,
                winnerTeamId: career.league.teams.first.id,
                periodScoresHome: const {},
                periodScoresAway: const {},
                playerLines: const {},
              ),
            ),
          },
        ),
        throwsFormatException,
      );
      final state = _state(career);
      final wrongSeed = RegularSeasonState(
        seasonId: state.seasonId,
        seasonYear: state.seasonYear,
        scheduleSeed: state.scheduleSeed + 1,
        openingTeams: state.openingTeams,
        gameResults: const {},
      );
      expect(
        () => career.copyWith(
          phase: CareerPhase.regularSeason,
          regularSeasonState: wrongSeed,
        ),
        throwsFormatException,
      );
    });

    test('entry snapshot rejects team identity drift', () {
      final career = _career();
      final state = _state(career);
      final teams = [...state.openingTeams];
      teams[0] = RegularSeasonTeamIdentity(
        teamId: teams[0].teamId,
        name: 'Forged franchise',
        abbreviation: teams[0].abbreviation,
      );
      final forged = RegularSeasonState(
        seasonId: state.seasonId,
        seasonYear: state.seasonYear,
        scheduleSeed: state.scheduleSeed,
        openingTeams: teams,
        gameResults: const {},
      );
      expect(
        () => career.copyWith(
          phase: CareerPhase.regularSeason,
          regularSeasonState: forged,
        ),
        throwsFormatException,
      );
    });
  });
}

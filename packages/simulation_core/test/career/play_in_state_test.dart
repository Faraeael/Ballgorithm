import 'package:simulation_core/simulation_core.dart';
import 'package:test/test.dart';

List<RegularSeasonTeamIdentity> _teams({bool validIds = true}) => [
  for (var index = 1; index <= 30; index++)
    RegularSeasonTeamIdentity(
      teamId: TeamId(validIds ? 'team-$index' : 'club-$index'),
      name: 'Club $index',
      abbreviation: 'C${index.toString().padLeft(2, '0')}',
    ),
];

RegularSeasonState _completedSeason({
  bool validIds = true,
  bool Function(RegularSeasonFixture fixture)? homeWins,
  int Function(RegularSeasonFixture fixture)? winningMargin,
}) {
  final teams = _teams(validIds: validIds);
  const seed = 20261028;
  final generated = const RegularSeasonScheduleGenerator().generate(
    seasonId: 'career-1-season-1',
    seasonYear: 1,
    scheduleSeed: seed,
    openingTeams: teams,
  );
  final results = <String, RegularSeasonGameResult>{};
  final schedule = RegularSeasonSchedule(
    seasonId: generated.seasonId,
    seasonYear: generated.seasonYear,
    scheduleSeed: generated.scheduleSeed,
    rounds: [
      for (final round in generated.rounds)
        RegularSeasonRound(
          roundNumber: round.roundNumber,
          fixtures: [
            for (final fixture in round.fixtures)
              RegularSeasonFixture(
                id: fixture.id,
                seasonId: fixture.seasonId,
                seasonYear: fixture.seasonYear,
                roundNumber: fixture.roundNumber,
                fixturePosition: fixture.fixturePosition,
                homeTeamId: fixture.homeTeamId,
                awayTeamId: fixture.awayTeamId,
                gameSeed: fixture.gameSeed,
                status: RegularSeasonFixtureStatus.completed,
              ),
          ],
        ),
    ],
  );
  for (final fixture in schedule.allFixtures) {
    final homeWon = homeWins?.call(fixture) ?? true;
    final margin = winningMargin?.call(fixture) ?? 10;
    final homeScore = homeWon ? 100 : 100 - margin;
    final awayScore = homeWon ? 100 - margin : 100;
    results[fixture.id] = RegularSeasonGameResult(
      fixtureId: fixture.id,
      seasonId: fixture.seasonId,
      seasonYear: fixture.seasonYear,
      homeTeamId: fixture.homeTeamId,
      awayTeamId: fixture.awayTeamId,
      gameSeed: fixture.gameSeed,
      inputFingerprint: List.filled(64, '0').join(),
      simulationVersion: 7,
      rulesVersion: 3,
      eventSchemaVersion: 3,
      prngImplementationId: 'xorshift32-v1',
      fingerprintVersion: 5,
      coreEngineVersion: '1.0.0',
      leagueSchemaVersion: 1,
      periodsPlayed: 4,
      summary: SeasonGameSummary(
        homeScore: homeScore,
        awayScore: awayScore,
        winnerTeamId: homeWon ? fixture.homeTeamId : fixture.awayTeamId,
        periodScoresHome: {'Q1': homeScore, 'Q2': 0, 'Q3': 0, 'Q4': 0},
        periodScoresAway: {'Q1': awayScore, 'Q2': 0, 'Q3': 0, 'Q4': 0},
        playerLines: const {},
      ),
    );
  }
  return RegularSeasonState(
    seasonId: schedule.seasonId,
    seasonYear: schedule.seasonYear,
    scheduleSeed: seed,
    openingTeams: teams,
    gameResults: results,
    schedule: schedule,
  );
}

bool _isPair(RegularSeasonFixture fixture, String first, String second) =>
    {fixture.homeTeamId.value, fixture.awayTeamId.value}.contains(first) &&
    {fixture.homeTeamId.value, fixture.awayTeamId.value}.contains(second);

RegularSeasonGameResult _playInResult(
  PlayInFixture fixture, {
  required bool homeWins,
  required String seasonId,
  required int seasonYear,
}) {
  final homeScore = homeWins ? 100 : 90;
  final awayScore = homeWins ? 90 : 100;
  return RegularSeasonGameResult(
    fixtureId: fixture.id,
    seasonId: seasonId,
    seasonYear: seasonYear,
    homeTeamId: fixture.homeTeamId,
    awayTeamId: fixture.awayTeamId,
    gameSeed: fixture.gameSeed,
    inputFingerprint: List.filled(64, '0').join(),
    simulationVersion: 7,
    rulesVersion: 3,
    eventSchemaVersion: 3,
    prngImplementationId: 'xorshift32-v1',
    fingerprintVersion: 5,
    coreEngineVersion: '1.0.0',
    leagueSchemaVersion: 1,
    inputEvidence: RegularSeasonGameInputEvidence(
      leagueSnapshotId: 'snapshot-${fixture.id}',
      payloadTemplateJson: '{}',
    ),
    periodsPlayed: 4,
    summary: SeasonGameSummary(
      homeScore: homeScore,
      awayScore: awayScore,
      winnerTeamId: homeWins ? fixture.homeTeamId : fixture.awayTeamId,
      periodScoresHome: {'Q1': homeScore, 'Q2': 0, 'Q3': 0, 'Q4': 0},
      periodScoresAway: {'Q1': awayScore, 'Q2': 0, 'Q3': 0, 'Q4': 0},
      playerLines: const {},
    ),
  );
}

void main() {
  group('Play-In ranking and fixtures', () {
    test('ranks tied records by numeric generated team ordinal', () {
      final season = _completedSeason();
      final ranking = PlayInRanking.rank(season);
      expect(ranking, [for (var id = 1; id <= 30; id++) TeamId('team-$id')]);
    });

    test('rejects IDs outside the generated team-N franchise domain', () {
      expect(
        () => PlayInRanking.rank(_completedSeason(validIds: false)),
        throwsFormatException,
      );
    });

    test('persists G1 and G2 seeds and validates disjoint seed namespace', () {
      final season = _completedSeason();
      final ranking = PlayInRanking.rank(season);
      final state = PlayInState.initial(
        seasonId: season.seasonId,
        seasonYear: season.seasonYear,
        scheduleSeed: season.scheduleSeed,
        originalRanking: ranking,
      );
      state.validate(regularSeasonState: season);
      final game1 = state.fixture(
        gameNumber: 1,
        scheduleSeed: season.scheduleSeed,
      )!;
      final game2 = state.fixture(
        gameNumber: 2,
        scheduleSeed: season.scheduleSeed,
      )!;
      expect(game1.homeTeamId, ranking[14]);
      expect(game1.awayTeamId, ranking[15]);
      expect(game1.rematchIndex, 83);
      expect(game2.homeTeamId, ranking[16]);
      expect(game2.awayTeamId, ranking[17]);
      expect(game2.rematchIndex, 84);
      expect(game1.gameSeed, isNot(game2.gameSeed));
      expect(
        state.fixture(gameNumber: 3, scheduleSeed: season.scheduleSeed),
        isNull,
      );
      final decoded = PlayInState.fromJson(state.toJson());
      expect(decoded.gameIdentities, hasLength(3));
      expect(decoded.gameIdentities[0].gameSeed, game1.gameSeed);
      expect(decoded.gameIdentities[1].gameSeed, game2.gameSeed);
    });

    test(
      'two-team head-to-head breaks tied wins ahead of point differential',
      () {
        final template = _completedSeason();
        final pairMeetings = template.schedule!.allFixtures
            .where((fixture) => _isPair(fixture, 'team-1', 'team-2'))
            .toList();
        final adjustments = pairMeetings.length ~/ 2;
        final team1 = const TeamId('team-1');
        final team2 = const TeamId('team-2');
        final overrides = <String, TeamId>{};
        for (final fixture in pairMeetings) {
          if (fixture.homeTeamId == team2) {
            overrides[fixture.id] = team1;
          }
        }
        void flipAwayWin(TeamId home, TeamId away) {
          final fixture = template.schedule!.allFixtures.firstWhere(
            (candidate) =>
                candidate.homeTeamId == home && candidate.awayTeamId == away,
          );
          overrides[fixture.id] = away;
        }

        final positiveTeams = [
          for (var index = 0; index < 14; index++) TeamId('team-${3 + index}'),
        ];
        final negativeTeams = [
          for (var index = 0; index < 14; index++) TeamId('team-${17 + index}'),
        ];
        for (var index = 0; index < adjustments; index++) {
          flipAwayWin(team1, positiveTeams[index]);
          flipAwayWin(negativeTeams[index], team2);
        }
        for (var index = adjustments; index < 14; index++) {
          flipAwayWin(negativeTeams[index], positiveTeams[index]);
        }
        final team2Wins = <String>{};
        final season = _completedSeason(
          homeWins: (fixture) {
            final winner = overrides[fixture.id] ?? fixture.homeTeamId;
            if (winner == team2) team2Wins.add(fixture.id);
            return winner == fixture.homeTeamId;
          },
          winningMargin: (fixture) => team2Wins.contains(fixture.id) ? 80 : 1,
        );
        final standings = season.standings;
        expect(standings.table[team1.value]!.wins, 41);
        expect(standings.table[team2.value]!.wins, 41);
        expect(
          standings.table.values.where((standing) => standing.wins == 41),
          hasLength(2),
        );
        expect(
          standings.table[team2.value]!.pointDifferential,
          greaterThan(standings.table[team1.value]!.pointDifferential),
        );
        final ranking = PlayInRanking.rank(season);
        expect(ranking.indexOf(team1), lessThan(ranking.indexOf(team2)));
      },
    );

    test('split two-team head-to-head falls through to point differential', () {
      final template = _completedSeason();
      final team1 = const TeamId('team-1');
      final team2 = const TeamId('team-2');
      final pairMeetings = template.schedule!.allFixtures
          .where((fixture) => _isPair(fixture, 'team-1', 'team-2'))
          .toList();
      expect(pairMeetings, hasLength(4));
      final flippedFixtures = {
        for (var index = 0; index < 14; index++)
          template.schedule!.allFixtures
              .firstWhere(
                (fixture) =>
                    fixture.homeTeamId.value == 'team-${17 + index}' &&
                    fixture.awayTeamId.value == 'team-${3 + index}',
              )
              .id,
      };
      final season = _completedSeason(
        homeWins: (fixture) => !flippedFixtures.contains(fixture.id),
        winningMargin: (fixture) {
          if (_isPair(fixture, team1.value, team2.value)) {
            return fixture.homeTeamId == team2 ? 80 : 1;
          }
          return 10;
        },
      );
      final standings = season.standings;
      expect(standings.table[team1.value]!.wins, 41);
      expect(standings.table[team2.value]!.wins, 41);
      expect(
        standings.table.values.where((standing) => standing.wins == 41),
        hasLength(2),
      );
      expect(
        standings.table[team1.value]!.pointDifferential,
        lessThan(standings.table[team2.value]!.pointDifferential),
      );
      var team1HeadToHeadWins = 0;
      var team2HeadToHeadWins = 0;
      for (final fixture in pairMeetings) {
        final winner = season.gameResults[fixture.id]!.summary.winnerTeamId;
        if (winner == team1) team1HeadToHeadWins++;
        if (winner == team2) team2HeadToHeadWins++;
      }
      expect(team1HeadToHeadWins, 2);
      expect(team2HeadToHeadWins, 2);
      final ranking = PlayInRanking.rank(season);
      expect(ranking.indexOf(team2), lessThan(ranking.indexOf(team1)));
    });

    test('three-or-more tied-wins group skips split head-to-head', () {
      final template = _completedSeason();
      final meetings = template.schedule!.allFixtures
          .where((fixture) => _isPair(fixture, 'team-1', 'team-2'))
          .toList();
      final season = _completedSeason(
        winningMargin: (fixture) =>
            fixture.homeTeamId.value == 'team-2' ? 80 : 1,
      );
      final standings = season.standings;
      expect(standings.table['team-1']!.wins, standings.table['team-2']!.wins);
      final tiedGroup = standings.table.values
          .where((record) => record.wins == standings.table['team-1']!.wins)
          .toList();
      expect(tiedGroup.length, greaterThanOrEqualTo(3));
      final directWins = {'team-1': 0, 'team-2': 0};
      for (final fixture in meetings) {
        final winner =
            season.gameResults[fixture.id]!.summary.winnerTeamId.value;
        directWins[winner] = directWins[winner]! + 1;
      }
      expect(directWins['team-1'], directWins['team-2']);
      expect(PlayInRanking.rank(season).first, const TeamId('team-2'));
    });

    test('all eight Play-In outcome paths produce unique seeds 15 and 16', () {
      final season = _completedSeason();
      final ranking = PlayInRanking.rank(season);
      final initial = PlayInState.initial(
        seasonId: season.seasonId,
        seasonYear: season.seasonYear,
        scheduleSeed: season.scheduleSeed,
        originalRanking: ranking,
      );
      final game3Seeds = <int>{};
      for (final game1HomeWins in [false, true]) {
        for (final game2HomeWins in [false, true]) {
          for (final game3HomeWins in [false, true]) {
            final game1 = initial.fixture(
              gameNumber: 1,
              scheduleSeed: season.scheduleSeed,
            )!;
            var state = initial.withResult(
              result: _playInResult(
                game1,
                homeWins: game1HomeWins,
                seasonId: season.seasonId,
                seasonYear: season.seasonYear,
              ),
              leagueSnapshotJson: '{}',
              scheduleSeed: season.scheduleSeed,
            );
            expect(
              state.fixture(gameNumber: 3, scheduleSeed: season.scheduleSeed),
              isNull,
            );
            final game2 = state.fixture(
              gameNumber: 2,
              scheduleSeed: season.scheduleSeed,
            )!;
            state = state.withResult(
              result: _playInResult(
                game2,
                homeWins: game2HomeWins,
                seasonId: season.seasonId,
                seasonYear: season.seasonYear,
              ),
              leagueSnapshotJson: '{}',
              scheduleSeed: season.scheduleSeed,
            );
            final game3 = state.fixture(
              gameNumber: 3,
              scheduleSeed: season.scheduleSeed,
            )!;
            expect(game3.homeTeamId, game1HomeWins ? ranking[15] : ranking[14]);
            expect(game3.awayTeamId, game2HomeWins ? ranking[16] : ranking[17]);
            state = state.withResult(
              result: _playInResult(
                game3,
                homeWins: game3HomeWins,
                seasonId: season.seasonId,
                seasonYear: season.seasonYear,
              ),
              leagueSnapshotJson: '{}',
              scheduleSeed: season.scheduleSeed,
            );
            game3Seeds.add(game3.gameSeed);
            final reloaded = PlayInState.fromJson(state.toJson());
            expect(
              reloaded
                  .fixture(gameNumber: 3, scheduleSeed: season.scheduleSeed)!
                  .gameSeed,
              game3.gameSeed,
            );
            expect(state.isComplete, isTrue);
            final game1Result = state.gameResults[game1.id]!;
            final game2Result = state.gameResults[game2.id]!;
            final game3Result = state.gameResults[game3.id]!;
            final game1Winner = game1Result.summary.winnerTeamId;
            final game2Winner = game2Result.summary.winnerTeamId;
            final game2Loser = game2Winner == game2Result.homeTeamId
                ? game2Result.awayTeamId
                : game2Result.homeTeamId;
            final game3Winner = game3Result.summary.winnerTeamId;
            final game3Loser = game3Winner == game3Result.homeTeamId
                ? game3Result.awayTeamId
                : game3Result.homeTeamId;
            expect(state.qualifiedTeams[14], (
              15,
              game1Winner,
              ranking.indexOf(game1Winner) + 1,
            ));
            expect(state.qualifiedTeams[15], (
              16,
              game3Winner,
              ranking.indexOf(game3Winner) + 1,
            ));
            expect(state.eliminatedTeams, {
              ...ranking.skip(18),
              game2Loser,
              game3Loser,
            });
            expect(state.qualifiedTeams, hasLength(16));
            expect(state.qualifiedTeams.map((team) => team.$1).toList(), [
              ...List.generate(14, (index) => index + 1),
              15,
              16,
            ]);
            expect(
              state.qualifiedTeams.map((team) => team.$2).toSet(),
              hasLength(16),
            );
            expect(state.eliminatedTeams, hasLength(14));
            expect(state.gameIdentities[2].homeTeamId, game3.homeTeamId);
            expect(state.gameIdentities[2].gameSeed, game3.gameSeed);
          }
        }
      }
      expect(game3Seeds, hasLength(4));
    });
  });
}

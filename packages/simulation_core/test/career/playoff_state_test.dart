import 'dart:convert';

import 'package:simulation_core/simulation_core.dart';
import 'package:simulation_core/src/season/season_seed.dart';
import 'package:test/test.dart';

const _seasonId = 'career-1-season-1';
const _scheduleSeed = 24680;
const _snapshotId = 'snapshot';

List<TeamId> _franchises() => [
  for (var index = 1; index <= 30; index++)
    TeamId('team-${index.toString().padLeft(2, '0')}'),
];

List<(int, TeamId, int)> _qualifications() => [
  for (var seed = 1; seed <= 16; seed++)
    (seed, TeamId('team-${seed.toString().padLeft(2, '0')}'), 17 - seed),
];

PlayoffState _initialState() => PlayoffState.initial(
  seasonId: _seasonId,
  seasonYear: 1,
  scheduleSeed: _scheduleSeed,
  qualifiedTeams: _qualifications(),
  franchiseIds: _franchises(),
);

RegularSeasonGameResult _result(PlayoffGameIdentity game, TeamId winner) =>
    RegularSeasonGameResult(
      fixtureId: game.id,
      seasonId: _seasonId,
      seasonYear: 1,
      homeTeamId: game.homeTeamId,
      awayTeamId: game.awayTeamId,
      gameSeed: game.gameSeed,
      inputFingerprint: List.filled(64, '0').join(),
      simulationVersion: 7,
      rulesVersion: 3,
      eventSchemaVersion: 3,
      prngImplementationId: 'xorshift32-v1',
      fingerprintVersion: 5,
      coreEngineVersion: '1.0.0',
      leagueSchemaVersion: 1,
      inputEvidence: const RegularSeasonGameInputEvidence(
        leagueSnapshotId: _snapshotId,
        payloadTemplateJson: '{}',
      ),
      periodsPlayed: 4,
      summary: SeasonGameSummary(
        homeScore: winner == game.homeTeamId ? 101 : 90,
        awayScore: winner == game.awayTeamId ? 101 : 90,
        winnerTeamId: winner,
        periodScoresHome: const {},
        periodScoresAway: const {},
        playerLines: const {},
      ),
    );

PlayoffState _addResults(
  PlayoffState state,
  Iterable<RegularSeasonGameResult> results,
) => state.withResults(
  results: results.toList(),
  addedSnapshots: const {_snapshotId: '{}'},
  scheduleSeed: _scheduleSeed,
  franchiseIds: _franchises(),
);

PlayoffState _sweepCurrentRound(PlayoffState state) {
  final results = <RegularSeasonGameResult>[];
  for (final game in state.nextEligibleGames) {
    final slot = state.seriesAt(game.seriesIndex);
    final firstTeam = slot.firstTeamId!;
    for (var gameNumber = 1; gameNumber <= 4; gameNumber++) {
      results.add(
        _result(state.gameIdentities['${slot.id}-g$gameNumber']!, firstTeam),
      );
    }
  }
  return _addResults(state, results);
}

void main() {
  test('rematch seed domain has no collisions for any ordered matchup', () {
    const leagueSeed = 0x13579BDF;
    final seeds = <int>{};
    for (var rematchIndex = 1; rematchIndex <= 190; rematchIndex++) {
      for (var homeIndex = 0; homeIndex < 30; homeIndex++) {
        for (var awayIndex = 0; awayIndex < 30; awayIndex++) {
          if (homeIndex == awayIndex) continue;
          final seed = deriveGameSeed(
            leagueSeed: leagueSeed,
            homeIndex: homeIndex,
            awayIndex: awayIndex,
            rematchIndex: rematchIndex,
          );
          if (!seeds.add(seed)) {
            fail(
              'Seed collision at rematch $rematchIndex, '
              'home $homeIndex, away $awayIndex',
            );
          }
        }
      }
    }
    expect(seeds, hasLength(190 * 30 * 29));
  });
  test('fixed bracket, original-rank home court, and all game slots', () {
    var state = _initialState();
    const firstRound = [
      (1, 16),
      (8, 9),
      (4, 13),
      (5, 12),
      (3, 14),
      (6, 11),
      (2, 15),
      (7, 10),
    ];
    for (var index = 0; index < firstRound.length; index++) {
      final slot = state.seriesAt(index);
      final (firstSeed, secondSeed) = firstRound[index];
      expect(slot.firstTeamId, state.qualifiedTeams[firstSeed - 1].teamId);
      expect(slot.secondTeamId, state.qualifiedTeams[secondSeed - 1].teamId);
    }

    final qualifications = {
      for (final team in state.qualifiedTeams)
        team.teamId: team.originalRegularSeasonRank,
    };

    for (var round = 0; round < 4; round++) {
      state = _sweepCurrentRound(state);
      if (round == 0) {
        const quarterfinalSeeds = [(1, 8), (4, 5), (3, 6), (2, 7)];
        for (var index = 0; index < quarterfinalSeeds.length; index++) {
          final (firstSeed, secondSeed) = quarterfinalSeeds[index];
          expect(
            state.seriesAt(index + 8).firstTeamId,
            state.qualifiedTeams[firstSeed - 1].teamId,
          );
          expect(
            state.seriesAt(index + 8).secondTeamId,
            state.qualifiedTeams[secondSeed - 1].teamId,
          );
        }
      } else if (round == 1) {
        const semifinalSeeds = [(1, 4), (3, 2)];
        for (var index = 0; index < semifinalSeeds.length; index++) {
          final (firstSeed, secondSeed) = semifinalSeeds[index];
          expect(
            state.seriesAt(index + 12).firstTeamId,
            state.qualifiedTeams[firstSeed - 1].teamId,
          );
          expect(
            state.seriesAt(index + 12).secondTeamId,
            state.qualifiedTeams[secondSeed - 1].teamId,
          );
        }
      } else if (round == 2) {
        expect(state.seriesAt(14).firstTeamId, state.qualifiedTeams[0].teamId);
        expect(state.seriesAt(14).secondTeamId, state.qualifiedTeams[2].teamId);
      }
    }

    const earlyHomeGames = {1, 2, 5, 7};
    for (final game in state.gameIdentities.values) {
      final firstIsHigher =
          qualifications[game.homeTeamId]! < qualifications[game.awayTeamId]!;
      final higherRankTeam = firstIsHigher ? game.homeTeamId : game.awayTeamId;
      final lowerRankTeam = firstIsHigher ? game.awayTeamId : game.homeTeamId;
      expect(
        game.homeTeamId,
        earlyHomeGames.contains(game.gameNumber)
            ? higherRankTeam
            : lowerRankTeam,
      );
      expect(
        game.rematchIndex,
        86 + game.seriesIndex * 7 + game.gameNumber - 1,
      );
    }
    expect(state.isComplete, isTrue);
    expect(state.champion, state.qualifiedTeams[0].teamId);
    expect(state.gameResults, hasLength(60));
    expect(state.gameIdentities, hasLength(105));
    expect(
      state.gameIdentities.values.map((game) => game.id).toSet(),
      hasLength(105),
    );
    expect(
      state.gameIdentities.values.map((game) => game.rematchIndex).toSet(),
      hasLength(105),
    );
    expect(
      state.gameIdentities.values.map((game) => game.gameSeed).toSet(),
      hasLength(105),
    );
    expect(
      state.gameIdentities.values.map((game) => game.rematchIndex).toSet(),
      containsAll(List.generate(105, (index) => 86 + index)),
    );
    expect(state.eliminatedTeams, hasLength(15));
    expect(state.nextEligibleGames, isEmpty);
    expect(state.currentRound, isNull);
    final openingTeams = [
      for (var index = 1; index <= 30; index++)
        RegularSeasonTeamIdentity(
          teamId: TeamId('team-${index.toString().padLeft(2, '0')}'),
          name: 'Team $index',
          abbreviation: 'T${index.toString().padLeft(2, '0')}',
        ),
    ];
    final schedule = const RegularSeasonScheduleGenerator().generate(
      seasonId: _seasonId,
      seasonYear: 1,
      scheduleSeed: _scheduleSeed,
      openingTeams: openingTeams,
    );
    final canonicalIds = _franchises().map((team) => team.value).toList()
      ..sort();
    int teamIndex(TeamId team) => canonicalIds.indexOf(team.value);
    int normalizedSeed(TeamId home, TeamId away, int rematchIndex) {
      final seed = deriveGameSeed(
        leagueSeed: _scheduleSeed,
        homeIndex: teamIndex(home),
        awayIndex: teamIndex(away),
        rematchIndex: rematchIndex,
      );
      return seed == 0 ? 0x9E3779B9 : seed;
    }

    final regularSeeds = {
      for (final fixture in schedule.allFixtures)
        fixture.gameSeed == 0 ? 0x9E3779B9 : fixture.gameSeed,
    };
    final playInSeeds = {
      normalizedSeed(const TeamId('team-15'), const TeamId('team-16'), 83),
      normalizedSeed(const TeamId('team-17'), const TeamId('team-18'), 84),
      for (final home in [const TeamId('team-15'), const TeamId('team-16')])
        for (final away in [const TeamId('team-17'), const TeamId('team-18')])
          normalizedSeed(home, away, 85),
    };
    final playoffSeeds = {
      for (final game in state.gameIdentities.values)
        game.gameSeed == 0 ? 0x9E3779B9 : game.gameSeed,
    };
    expect(schedule.totalFixtures, 1230);
    expect(regularSeeds, hasLength(1230));
    expect(playInSeeds, hasLength(6));
    expect(playoffSeeds, hasLength(105));
    expect(regularSeeds.intersection(playInSeeds), isEmpty);
    expect(regularSeeds.intersection(playoffSeeds), isEmpty);
    expect(playInSeeds.intersection(playoffSeeds), isEmpty);
  });

  test(
    'series supports every legal best-of-seven finish and rejects Game 8',
    () {
      for (var length = 4; length <= 7; length++) {
        var state = _initialState();
        final slot = state.seriesAt(0);
        final first = slot.firstTeamId!;
        final second = slot.secondTeamId!;
        final losses = length - 4;
        final legalWinners = <TeamId>[
          for (var index = 0; index < losses; index++) ...[first, second],
          for (var index = 0; index < 4 - losses; index++) first,
        ];
        final results = [
          for (var gameNumber = 1; gameNumber <= length; gameNumber++)
            _result(
              state.gameIdentities['${slot.id}-g$gameNumber']!,
              legalWinners[gameNumber - 1],
            ),
        ];
        state = _addResults(state, results);
        expect(state.seriesWins(0, first), 4);
        expect(state.seriesWins(0, second), losses);
        expect(state.seriesWinner(0), first);
        if (length < 7) {
          expect(
            () => _addResults(state, [
              _result(
                state.gameIdentities['${slot.id}-g${length + 1}']!,
                second,
              ),
            ]),
            throwsFormatException,
          );
        } else {
          expect(state.gameIdentities.containsKey('${slot.id}-g8'), isFalse);
        }
      }
    },
  );

  test(
    'save and reload preserves identities, results, and derived advancement',
    () {
      var state = _initialState();
      state = _sweepCurrentRound(state);
      final restored = PlayoffState.fromJson(
        jsonDecode(jsonEncode(state.toJson())) as Map<String, dynamic>,
      );
      expect(restored.toJson(), state.toJson());
      expect(restored.seriesAt(8).firstTeamId, state.seriesAt(8).firstTeamId);
      expect(
        restored.nextEligibleGames.map((game) => game.id).toList(),
        state.nextEligibleGames.map((game) => game.id).toList(),
      );
    },
  );

  test('later series resolve only after both feeder series are complete', () {
    var state = _initialState();
    final firstFeeder = state.seriesAt(6);
    final firstWinner = firstFeeder.firstTeamId!;
    state = _addResults(state, [
      for (var gameNumber = 1; gameNumber <= 4; gameNumber++)
        _result(
          state.gameIdentities['${firstFeeder.id}-g$gameNumber']!,
          firstWinner,
        ),
    ]);
    expect(state.seriesWinner(6), firstWinner);
    expect(state.seriesAt(11).firstTeamId, isNull);
    expect(state.seriesAt(11).secondTeamId, isNull);
    expect(
      state.gameIdentities.values.where((game) => game.seriesIndex == 11),
      isEmpty,
    );

    final secondFeeder = state.seriesAt(7);
    final secondWinner = secondFeeder.secondTeamId!;
    state = _addResults(state, [
      for (var gameNumber = 1; gameNumber <= 4; gameNumber++)
        _result(
          state.gameIdentities['${secondFeeder.id}-g$gameNumber']!,
          secondWinner,
        ),
    ]);
    expect(state.seriesAt(11).firstTeamId, firstWinner);
    expect(state.seriesAt(11).secondTeamId, secondWinner);
    expect(
      state.gameIdentities.values.where((game) => game.seriesIndex == 11),
      hasLength(7),
    );
  });
}

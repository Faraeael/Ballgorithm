import 'package:simulation_core/simulation_core.dart';
import 'package:test/test.dart';

void main() {
  group('SeasonPlayerTotals', () {
    test('initializes with zeros and handles zero-denominator safe rates', () {
      final initial = SeasonPlayerTotals.initial(
        playerId: 'player-1',
        teamId: 'team-1',
      );

      expect(initial.gamesPlayed, 0);
      expect(initial.secondsPlayed, 0);
      expect(initial.points, 0);
      expect(initial.fieldGoalPercentage, isNull);
      expect(initial.threePointPercentage, isNull);
      expect(initial.freeThrowPercentage, isNull);
      expect(initial.pointsPerGame, 0.0);
      expect(initial.minutesPerGame, 0.0);
      expect(initial.reboundsPerGame, 0.0);
      expect(initial.assistsPerGame, 0.0);
    });

    test(
      'accumulates game lines correctly and computes shooting percentages',
      () {
        var totals = SeasonPlayerTotals.initial(
          playerId: 'player-1',
          teamId: 'team-1',
        );

        // Game 1
        const line1 = SeasonPlayerGameLine(
          playerId: 'player-1',
          teamId: 'team-1',
          points: 25,
          fgm: 10,
          fga: 20,
          threePm: 3,
          threePa: 6,
          ftm: 2,
          fta: 2,
          oreb: 1,
          dreb: 5,
          rebounds: 6,
          assists: 7,
          steals: 2,
          blocks: 1,
          turnovers: 3,
          personalFouls: 2,
          secondsPlayed: 1800, // 30 minutes
        );

        totals = totals.applyGame(line1);

        expect(totals.gamesPlayed, 1);
        expect(totals.secondsPlayed, 1800);
        expect(totals.minutesPerGame, 30.0);
        expect(totals.points, 25);
        expect(totals.pointsPerGame, 25.0);
        expect(totals.fieldGoalPercentage, 0.5);
        expect(totals.threePointPercentage, 0.5);
        expect(totals.freeThrowPercentage, 1.0);
        expect(totals.rebounds, 6);
        expect(totals.reboundsPerGame, 6.0);
        expect(totals.assists, 7);
        expect(totals.assistsPerGame, 7.0);

        // Game 2
        const line2 = SeasonPlayerGameLine(
          playerId: 'player-1',
          teamId: 'team-1',
          points: 15,
          fgm: 5,
          fga: 10,
          threePm: 1,
          threePa: 4,
          ftm: 4,
          fta: 6,
          oreb: 2,
          dreb: 4,
          rebounds: 6,
          assists: 3,
          steals: 1,
          blocks: 0,
          turnovers: 1,
          personalFouls: 3,
          secondsPlayed: 2160, // 36 minutes
        );

        totals = totals.applyGame(line2);

        expect(totals.gamesPlayed, 2);
        expect(totals.secondsPlayed, 3960); // 66 minutes
        expect(totals.minutesPerGame, 33.0);
        expect(totals.points, 40);
        expect(totals.pointsPerGame, 20.0);
        expect(totals.fgm, 15);
        expect(totals.fga, 30);
        expect(totals.fieldGoalPercentage, 0.5);
        expect(totals.threePm, 4);
        expect(totals.threePa, 10);
        expect(totals.threePointPercentage, 0.4);
        expect(totals.ftm, 6);
        expect(totals.fta, 8);
        expect(totals.freeThrowPercentage, 0.75);
        expect(totals.rebounds, 12);
        expect(totals.reboundsPerGame, 6.0);
        expect(totals.assists, 10);
        expect(totals.assistsPerGame, 5.0);
      },
    );
  });
}

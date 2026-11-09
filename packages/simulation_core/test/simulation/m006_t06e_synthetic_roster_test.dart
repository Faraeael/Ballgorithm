import 'package:simulation_core/simulation_core.dart';
import 'package:test/test.dart';

import '../../tool/m006_pilot_runner.dart';

void main() {
  group('M006-T06E Synthetic Roster Verification', () {
    final baseLeague = const LeagueGenerator().generate(
      const GenerationConfig(seed: 20261028),
    );
    final synLeague = buildSyntheticStretchFiveLeague(baseLeague);

    test('exact registered attributes for Team 1 Center (player-1-8)', () {
      final team1 = synLeague.teams.firstWhere((t) => t.id.value == 'team-1');
      final c1 = team1.players.firstWhere((p) => p.id.value == 'player-1-8');

      expect(c1.position, Position.c);
      final attr = c1.attributes;
      expect(attr.insideScoring, 75);
      expect(attr.midrange, 55);
      expect(attr.threePoint, 80);
      expect(attr.freeThrow, 75);
      expect(attr.passing, 60);
      expect(attr.ballHandling, 55);
      expect(attr.perimeterDefense, 50);
      expect(attr.interiorDefense, 65);
      expect(attr.rebounding, 70);
      expect(attr.athleticism, 60);
      expect(attr.stamina, 70);
      expect(attr.basketballIQ, 62);
    });

    test('exact registered attributes for Team 2 Center (player-2-5)', () {
      final team2 = synLeague.teams.firstWhere((t) => t.id.value == 'team-2');
      final c2 = team2.players.firstWhere((p) => p.id.value == 'player-2-5');

      expect(c2.position, Position.c);
      final attr = c2.attributes;
      expect(attr.insideScoring, 70);
      expect(attr.midrange, 65);
      expect(attr.threePoint, 78);
      expect(attr.freeThrow, 75);
      expect(attr.passing, 55);
      expect(attr.ballHandling, 50);
      expect(attr.perimeterDefense, 50);
      expect(attr.interiorDefense, 65);
      expect(attr.rebounding, 70);
      expect(attr.athleticism, 65);
      expect(attr.stamina, 70);
      expect(attr.basketballIQ, 60);
    });

    test('exactly two players are modified across the entire league', () {
      var diffCount = 0;
      for (final team in synLeague.teams) {
        final baseTeam = baseLeague.teams.firstWhere(
          (t) => t.id.value == team.id.value,
        );
        for (var i = 0; i < team.players.length; i++) {
          final pSyn = team.players[i];
          final pBase = baseTeam.players[i];
          expect(pSyn.id, pBase.id);
          expect(pSyn.position, pBase.position);
          expect(pSyn.firstName, pBase.firstName);
          expect(pSyn.lastName, pBase.lastName);

          if (pSyn.attributes.toJson().toString() !=
              pBase.attributes.toJson().toString()) {
            diffCount++;
            expect(
              pSyn.id.value == 'player-1-8' || pSyn.id.value == 'player-2-5',
              isTrue,
              reason: 'Only player-1-8 and player-2-5 should be modified',
            );
          }
        }
      }
      expect(diffCount, 2);
    });

    test(
      'both modified centers start in Slot 4 (Center) in default lineups',
      () {
        final home = synLeague.teams.firstWhere((t) => t.id.value == 'team-1');
        final away = synLeague.teams.firstWhere((t) => t.id.value == 'team-2');

        final homeLineup = CourtLineup.defaultFor(home);
        final awayLineup = CourtLineup.defaultFor(away);

        expect(homeLineup.slotAt(4), Position.c);
        expect(homeLineup.playerAtSlotIndex(4).id.value, 'player-1-8');

        expect(awayLineup.slotAt(4), Position.c);
        expect(awayLineup.playerAtSlotIndex(4).id.value, 'player-2-5');
      },
    );

    test('balanced rotation plan conserves minutes for synthetic league', () {
      final home = synLeague.teams.firstWhere((t) => t.id.value == 'team-1');
      final homeLineup = CourtLineup.defaultFor(home);
      final rules = GameRules.standard;

      final targets = RotationPlan.expandPreset(
        preset: RotationPreset.balanced,
        team: home,
        lineup: homeLineup,
        rules: rules,
      );

      final totalSeconds = targets.values.reduce((a, b) => a + b);
      expect(totalSeconds, 5 * 48 * 60); // 14400 seconds
      expect(
        targets[PlayerId('player-1-8')],
        greaterThan(25 * 60),
      ); // starter minutes
    });

    test(
      'validates Population A, B, and C metric separation across substitutions',
      () {
        final home = synLeague.teams.firstWhere((t) => t.id.value == 'team-1');
        final away = synLeague.teams.firstWhere((t) => t.id.value == 'team-2');
        final homeLineup = CourtLineup.defaultFor(home);
        final awayLineup = CourtLineup.defaultFor(away);
        final rules = GameRules.standard;

        final input = GameInput.create(
          gameId: 'test-pop-abc',
          league: synLeague,
          homeTeamId: home.id,
          awayTeamId: away.id,
          homeLineup: homeLineup,
          awayLineup: awayLineup,
          seed: 42,
          rules: rules,
        );

        // Lineup 1: default (player-1-8 in Slot 4 C, player-1-4 in Slot 3 PF, player-1-1 in Slot 1 SG)
        // Shot 1: player-1-8 in Slot 4 (Center)
        // Sub 1: player-1-8 moves to Slot 3 (PF), player-1-11 takes Slot 4 (C)
        // Shot 2: player-1-8 in Slot 3 (PF)
        // Sub 2: player-1-10 (SG with 3pt=70) moves into Slot 3 (PF)
        // Shot 3: player-1-10 in Slot 3 (PF)
        // Sub 3: player-1-10 moves back to Slot 1 (SG)
        // Shot 4: player-1-10 in Slot 1 (SG)

        final events = <GameEvent>[
          GameStarted(
            sequence: 1,
            period: 1,
            gameClock: 720,
            shotClock: null,
            homeTeamId: 'team-1',
            awayTeamId: 'team-2',
            startingTeamId: 'team-1',
          ),
          // Shot 1: player-1-8 at Slot 4 C
          FieldGoalAttempt(
            sequence: 2,
            period: 1,
            gameClock: 700,
            shotClock: 20,
            teamId: 'team-1',
            shooterId: 'player-1-8',
            shotValue: 3,
            made: true,
            andOne: false,
          ),
          // Sub 1: player-1-8 takes Slot 3 (PF, replacing player-1-4)
          Substitution(
            sequence: 3,
            period: 1,
            gameClock: 600,
            shotClock: null,
            teamId: 'team-1',
            playerOutId: 'player-1-8',
            playerInId: 'player-1-11',
            reason: SubstitutionReason.tactical,
          ),
          Substitution(
            sequence: 4,
            period: 1,
            gameClock: 600,
            shotClock: null,
            teamId: 'team-1',
            playerOutId: 'player-1-4',
            playerInId: 'player-1-8',
            reason: SubstitutionReason.tactical,
          ),
          // Shot 2: player-1-8 at Slot 3 PF
          FieldGoalAttempt(
            sequence: 5,
            period: 1,
            gameClock: 550,
            shotClock: 15,
            teamId: 'team-1',
            shooterId: 'player-1-8',
            shotValue: 3,
            made: false,
            andOne: false,
          ),
          // Sub 2: player-1-10 (high-three wing, 3pt=70) takes Slot 3 (PF)
          Substitution(
            sequence: 6,
            period: 1,
            gameClock: 500,
            shotClock: null,
            teamId: 'team-1',
            playerOutId: 'player-1-8',
            playerInId: 'player-1-10',
            reason: SubstitutionReason.tactical,
          ),
          // Shot 3: player-1-10 at Slot 3 PF
          FieldGoalAttempt(
            sequence: 7,
            period: 1,
            gameClock: 450,
            shotClock: 18,
            teamId: 'team-1',
            shooterId: 'player-1-10',
            shotValue: 3,
            made: true,
            andOne: false,
          ),
          // Sub 3: player-1-10 moves to Slot 1 (SG), player-1-4 takes Slot 3 (PF)
          Substitution(
            sequence: 8,
            period: 1,
            gameClock: 400,
            shotClock: null,
            teamId: 'team-1',
            playerOutId: 'player-1-10',
            playerInId: 'player-1-4',
            reason: SubstitutionReason.tactical,
          ),
          Substitution(
            sequence: 9,
            period: 1,
            gameClock: 400,
            shotClock: null,
            teamId: 'team-1',
            playerOutId: 'player-1-1',
            playerInId: 'player-1-10',
            reason: SubstitutionReason.tactical,
          ),
          // Shot 4: player-1-10 at Slot 1 SG
          FieldGoalAttempt(
            sequence: 10,
            period: 1,
            gameClock: 350,
            shotClock: 12,
            teamId: 'team-1',
            shooterId: 'player-1-10',
            shotValue: 3,
            made: false,
            andOne: false,
          ),
          PeriodEnded(sequence: 11, period: 1, gameClock: 0, shotClock: null),
          GameEnded(
            sequence: 12,
            period: 1,
            gameClock: 0,
            shotClock: null,
            finalPeriod: 1,
          ),
        ];

        final ledger = GameEventLedger(
          gameId: input.gameId,
          inputFingerprint: GameFingerprint.of(input),
          events: events,
        );

        // Build minimal valid box score matching events
        final expectedSeconds = <String, int>{
          'player-1-1': 320,
          'player-1-2': 720,
          'player-1-3': 720,
          'player-1-4': 520,
          'player-1-8': 220,
          'player-1-10': 500,
          'player-1-11': 600,
        };

        final playerScores = <String, PlayerBoxScore>{};
        for (final p in home.players) {
          final fga = (p.id.value == 'player-1-8')
              ? 2
              : ((p.id.value == 'player-1-10') ? 2 : 0);
          final fgm = (p.id.value == 'player-1-8')
              ? 1
              : ((p.id.value == 'player-1-10') ? 1 : 0);
          playerScores[p.id.value] = PlayerBoxScore(
            playerId: p.id.value,
            teamId: 'team-1',
            points: fgm * 3,
            fgm: fgm,
            fga: fga,
            twoPm: 0,
            twoPa: 0,
            threePm: fgm,
            threePa: fga,
            ftm: 0,
            fta: 0,
            assists: 0,
            oreb: 0,
            dreb: 0,
            rebounds: 0,
            turnovers: 0,
            steals: 0,
            blocks: 0,
            personalFouls: 0,
            secondsPlayed: expectedSeconds[p.id.value] ?? 0,
          );
        }
        for (final p in away.players) {
          final isStarter = awayLineup.containsPlayer(p.id);
          playerScores[p.id.value] = PlayerBoxScore(
            playerId: p.id.value,
            teamId: 'team-2',
            points: 0,
            fgm: 0,
            fga: 0,
            twoPm: 0,
            twoPa: 0,
            threePm: 0,
            threePa: 0,
            ftm: 0,
            fta: 0,
            assists: 0,
            oreb: 0,
            dreb: 0,
            rebounds: 0,
            turnovers: 0,
            steals: 0,
            blocks: 0,
            personalFouls: 0,
            secondsPlayed: isStarter ? 720 : 0,
          );
        }

        final teamScores = {
          'team-1': TeamBoxScore(
            teamId: 'team-1',
            points: 6,
            fgm: 2,
            fga: 4,
            twoPm: 0,
            twoPa: 0,
            threePm: 2,
            threePa: 4,
            ftm: 0,
            fta: 0,
            assists: 0,
            oreb: 0,
            dreb: 0,
            rebounds: 0,
            turnovers: 0,
            steals: 0,
            blocks: 0,
            personalFouls: 0,
          ),
          'team-2': TeamBoxScore(
            teamId: 'team-2',
            points: 0,
            fgm: 0,
            fga: 0,
            twoPm: 0,
            twoPa: 0,
            threePm: 0,
            threePa: 0,
            ftm: 0,
            fta: 0,
            assists: 0,
            oreb: 0,
            dreb: 0,
            rebounds: 0,
            turnovers: 0,
            steals: 0,
            blocks: 0,
            personalFouls: 0,
          ),
        };

        final result = GameResult(
          input: input,
          inputFingerprint: 'test',
          ledger: ledger,
          state: GameState.initial,
          boxScore: GameBoxScore(
            players: playerScores,
            teams: teamScores,
            periodPoints: {
              'team-1': {1: 6},
              'team-2': {1: 0},
            },
          ),
          homeScore: 6,
          awayScore: 0,
          periodsPlayed: 1,
          possessions: 0,
          simulationVersion: 7,
          rulesVersion: 3,
          eventSchemaVersion: 3,
          prngImplementationId: 'test',
        );

        final row = analyzeResult(result);

        // Verification:
        // Shot 1: player-1-8 at C  -> Pop A=1, Pop B=1, Pop C=1
        // Shot 2: player-1-8 at PF -> Pop A=0, Pop B=1, Pop C=1
        // Shot 3: player-1-10 at PF -> Pop A=0, Pop B=0, Pop C=1
        // Shot 4: player-1-10 at SG -> Pop A=0, Pop B=0, Pop C=0
        //
        // Totals:
        // Population A (genuineCenterFga): 1 FGA, 1 3PA
        // Population B (registeredCenterBigFga): 2 FGA, 2 3PA
        // Population C (stretchBigFga): 3 FGA, 3 3PA

        expect(
          row['stretchCenterFga'],
          1,
          reason: 'Pop A (C slot only) must be exactly 1',
        );
        expect(
          row['registeredCenterBigFga'],
          2,
          reason: 'Pop B (Registered Center PF/C) must be exactly 2',
        );
        expect(
          row['stretchBigFga'],
          3,
          reason: 'Pop C (General PF/C stretch bigs) must be exactly 3',
        );

        // Check player-level breakdown:
        final p1_8 = (row['players'] as List).firstWhere(
          (p) => p['playerId'] == 'player-1-8',
        );
        expect(p1_8['genuineCenterFga'], 1);
        expect(p1_8['registeredCenterBigFga'], 2);
        expect(p1_8['stretchBigFga'], 2);

        final p1_10 = (row['players'] as List).firstWhere(
          (p) => p['playerId'] == 'player-1-10',
        );
        expect(p1_10['genuineCenterFga'], 0);
        expect(
          p1_10['registeredCenterBigFga'],
          0,
          reason: 'Wing in PF must NEVER count for Pop B',
        );
        expect(
          p1_10['stretchBigFga'],
          1,
          reason: 'Wing in PF must count for Pop C',
        );
      },
    );
  });
}

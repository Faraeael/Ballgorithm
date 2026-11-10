import 'package:flutter/foundation.dart';
import 'package:simulation_core/simulation_core.dart';

import 'season_storage.dart';

class SeasonController extends ChangeNotifier {
  SeasonController({required this.league, required this.storage});

  final League league;
  final SeasonStorage storage;

  SeasonState? _state;
  bool _isLoading = false;
  bool _isCommitting = false;
  String? _errorMessage;

  SeasonState? get state => _state;
  bool get isLoading => _isLoading;
  bool get isCommitting => _isCommitting;
  String? get errorMessage => _errorMessage;
  bool get hasActiveSeason => _state != null;

  Future<void> loadSeason() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final raw = await storage.read();
      if (raw == null || raw.trim().isEmpty) {
        _state = null;
      } else {
        _state = SeasonCodec.decode(raw, existingLeague: league);
      }
    } catch (e) {
      _errorMessage =
          'Failed to load saved season: $e. Save file preserved without deletion.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> startNewSeason(TeamId userFranchiseId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final newState = SeasonState.initialize(
        league: league,
        userFranchiseId: userFranchiseId,
      );
      await storage.write(SeasonCodec.encode(newState));
      _state = newState;
    } catch (e) {
      _errorMessage = 'Failed to create new season: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> updateStrategy(FranchiseStrategy strategy) async {
    if (_state == null) return;
    try {
      final updated = _state!.updateStrategy(strategy);
      await storage.write(SeasonCodec.encode(updated));
      _state = updated;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to save strategy: $e';
      notifyListeners();
    }
  }

  Future<void> commitRoundWithUserResult(GameResult userGameResult) async {
    if (_isCommitting) return;
    final current = _state;
    if (current == null || current.isSeasonCompleted) return;

    final round = current.currentRound;
    if (round == null) return;

    final hasMatchingFixture = round.fixtures.any(
      (f) =>
          f.homeTeamId == userGameResult.homeTeamId &&
          f.awayTeamId == userGameResult.awayTeamId,
    );
    if (!hasMatchingFixture) return;
    _isCommitting = true;
    try {
      final simulator = GameSimulator();
      final allResults = <GameResult>[];

      for (final fixture in round.fixtures) {
        if (fixture.homeTeamId == userGameResult.homeTeamId &&
            fixture.awayTeamId == userGameResult.awayTeamId) {
          allResults.add(userGameResult);
        } else {
          final homeTeam = league.teams.firstWhere(
            (t) => t.id == fixture.homeTeamId,
          );
          final awayTeam = league.teams.firstWhere(
            (t) => t.id == fixture.awayTeamId,
          );

          final homeStrategy = FranchiseStrategy.defaultFor(homeTeam);
          final awayStrategy = FranchiseStrategy.defaultFor(awayTeam);

          final input = GameInput.create(
            gameId: fixture.id,
            league: league,
            homeTeamId: fixture.homeTeamId,
            awayTeamId: fixture.awayTeamId,
            homeLineup: homeStrategy.startingLineup,
            awayLineup: awayStrategy.startingLineup,
            rotationPlan: RotationPlan(
              home: homeStrategy.teamPlan,
              away: awayStrategy.teamPlan,
            ),
            seed: fixture.seed,
            rules: GameRules.standard,
          );
          allResults.add(simulator.simulate(input));
        }
      }

      final nextState = current.commitRound(
        roundNumber: round.roundNumber,
        results: allResults,
      );

      await storage.write(SeasonCodec.encode(nextState));
      _state = nextState;
      notifyListeners();
    } finally {
      _isCommitting = false;
    }
  }

  Future<void> resetSeason() async {
    await storage.clear();
    _state = null;
    _errorMessage = null;
    notifyListeners();
  }
}

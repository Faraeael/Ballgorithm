import 'package:flutter/foundation.dart';
import 'package:simulation_core/simulation_core.dart';

import '../game/game_runner.dart';
import 'season_storage.dart';

class SeasonController extends ChangeNotifier {
  SeasonController({
    required this.league,
    required this.storage,
    GameRunner? gameRunner,
  }) : _gameRunner = gameRunner ?? runGame;

  final League league;
  final SeasonStorage storage;
  final GameRunner _gameRunner;

  SeasonState? _state;
  bool _isLoading = false;
  bool _isCommitting = false;
  String? _errorMessage;
  GameResult? _pendingUserResult;

  SeasonState? get state => _state;
  bool get isLoading => _isLoading;
  bool get isCommitting => _isCommitting;
  String? get errorMessage => _errorMessage;
  bool get hasActiveSeason => _state != null;
  GameResult? get pendingUserResult => _pendingUserResult;
  bool get hasPendingResult => _pendingUserResult != null;

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

  /// Strictly validates user game result against pending fixture.
  void _validateUserGameResult(GameResult result, SeasonFixture fixture) {
    final legacyId =
        '${fixture.homeTeamId.value}-${fixture.awayTeamId.value}-${fixture.seed}';
    if (result.input.gameId != fixture.id && result.input.gameId != legacyId) {
      throw ArgumentError(
        'Result fixture ID (${result.input.gameId}) does not match scheduled fixture (${fixture.id})',
      );
    }
    if (result.input.seed != fixture.seed) {
      throw ArgumentError(
        'Result seed (${result.input.seed}) does not match scheduled fixture (${fixture.seed})',
      );
    }
    if (result.homeTeamId != fixture.homeTeamId ||
        result.awayTeamId != fixture.awayTeamId) {
      throw ArgumentError(
        'Result teams (${result.homeTeamId.value} vs ${result.awayTeamId.value}) do not match fixture (${fixture.homeTeamId.value} vs ${fixture.awayTeamId.value})',
      );
    }
    if (result.input.league.config.seed != league.config.seed) {
      throw ArgumentError('Result league seed does not match current league');
    }
    if (result.input.rules != GameRules.standard) {
      throw ArgumentError('Result rules do not match standard season rules');
    }
    if (result.simulationVersion != gameSimulationVersion) {
      throw ArgumentError('Result simulation version mismatch');
    }
    if (result.homeScore == result.awayScore) {
      throw ArgumentError('Game result cannot end in a tie');
    }

    final homeBox = result.boxScore.teams[result.homeTeamId.value];
    final awayBox = result.boxScore.teams[result.awayTeamId.value];
    if (homeBox == null || awayBox == null) {
      throw ArgumentError('Missing team box scores in result');
    }
    if (homeBox.points != result.homeScore ||
        awayBox.points != result.awayScore) {
      throw ArgumentError('Authoritative box score points do not match score');
    }
  }

  Future<void> commitRoundWithUserResult(GameResult userGameResult) async {
    if (_isCommitting) return;
    final current = _state;
    if (current == null || current.isSeasonCompleted) return;

    final round = current.currentRound;
    if (round == null) return;

    final userFixture = current.nextUserFixture;
    if (userFixture == null) return;

    // Validate user result strictly
    _validateUserGameResult(userGameResult, userFixture);

    _isCommitting = true;
    _pendingUserResult = userGameResult;
    _errorMessage = null;
    notifyListeners();

    try {
      final allResults = <GameResult>[];
      final backgroundRequests = <GameRequest>[];

      for (final fixture in round.fixtures) {
        if (fixture.id == userFixture.id) {
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

          backgroundRequests.add(
            GameRequest(
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
            ),
          );
        }
      }

      // Simulate background games asynchronously on worker isolates
      final backgroundResults = await Future.wait(
        backgroundRequests.map((req) => _gameRunner(req)),
      );
      allResults.addAll(backgroundResults);

      final nextState = current.commitRound(
        roundNumber: round.roundNumber,
        results: allResults,
      );

      // Persist atomically
      await storage.write(SeasonCodec.encode(nextState));

      // Successfully saved: advance state and clear pending result
      _state = nextState;
      _pendingUserResult = null;
      _errorMessage = null;
      notifyListeners();
    } catch (e) {
      // If simulation or persistence failed, retain previous state and keep pending result
      _errorMessage = 'Failed to commit round: $e';
      notifyListeners();
      rethrow;
    } finally {
      _isCommitting = false;
      notifyListeners();
    }
  }

  Future<void> retryPendingCommit() async {
    final pending = _pendingUserResult;
    if (pending != null) {
      await commitRoundWithUserResult(pending);
    }
  }

  Future<void> resetSeason() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await storage.clear();
      _state = null;
      _pendingUserResult = null;
      _errorMessage = null;
    } catch (e) {
      _errorMessage = 'Failed to delete saved season: $e';
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}

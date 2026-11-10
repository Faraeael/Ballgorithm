import 'package:flutter/material.dart';
import 'package:simulation_core/simulation_core.dart';

import 'game_result_view.dart';
import 'game_runner.dart';
import 'game_seed.dart';

/// Runs one confirmed game through the worker and renders exactly one state:
/// loading, failure or the results view.
///
/// The screen never invents a result: loading owns no score, success renders
/// only the returned `GameResult`, and failures expose typed validation codes.
/// Rematch advances the frozen seed cycle, one game at a time.
export 'game_runner.dart' show GameRunner;

class GameScreen extends StatefulWidget {
  const GameScreen({
    super.key,
    required this.request,
    this.runner = runGame,
    this.enableRematch = true,
    this.returnButtonLabel,
    this.onReturn,
    this.onGameFinished,
  });

  final GameRequest request;
  final GameRunner runner;
  final bool enableRematch;
  final String? returnButtonLabel;
  final VoidCallback? onReturn;
  final ValueChanged<GameResult>? onGameFinished;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

enum _GamePhase { loading, success, failure }

class _GameScreenState extends State<GameScreen> {
  static const int _rematchCycle = 256;

  _GamePhase _phase = _GamePhase.loading;
  GameResult? _result;
  Object? _failure;
  bool _running = false;
  int _attempt = 0;
  late GameRequest _currentRequest;
  late int _rematchIndex;
  bool _seedCycleRepeated = false;

  @override
  void initState() {
    super.initState();
    _currentRequest = widget.request;
    _rematchIndex = _rematchIndexForSeed(widget.request.seed);
    _startRun();
  }

  int? _teamIndex(TeamId id) {
    final index = widget.request.league.teams.indexWhere(
      (team) => team.id.value == id.value,
    );
    return index < 0 ? null : index;
  }

  /// Position of the incoming seed inside the bounded rematch cycle; `0` when
  /// the request was not produced by this derivation.
  int _rematchIndexForSeed(int seed) {
    final homeIndex = _teamIndex(widget.request.homeTeamId);
    final awayIndex = _teamIndex(widget.request.awayTeamId);
    if (homeIndex == null || awayIndex == null) return 0;
    for (var index = 0; index < _rematchCycle; index++) {
      if (deriveGameSeed(
            leagueSeed: widget.request.league.config.seed,
            homeIndex: homeIndex,
            awayIndex: awayIndex,
            rematchIndex: index,
          ) ==
          seed) {
        return index;
      }
    }
    return 0;
  }

  Future<void> _startRun() async {
    if (_running) return;
    _running = true;
    final attempt = ++_attempt;
    try {
      final result = await widget.runner(_currentRequest);
      if (!mounted || attempt != _attempt) return;
      setState(() {
        _result = result;
        _phase = _GamePhase.success;
      });
      widget.onGameFinished?.call(result);
    } catch (error) {
      if (!mounted || attempt != _attempt) return;
      setState(() {
        _failure = error;
        _phase = _GamePhase.failure;
      });
    } finally {
      if (mounted && attempt == _attempt) _running = false;
    }
  }

  void _retry() {
    if (_running) return;
    setState(() {
      _phase = _GamePhase.loading;
      _result = null;
      _failure = null;
    });
    _startRun();
  }

  void _rematch() {
    if (_running) return;
    final homeIndex = _teamIndex(_currentRequest.homeTeamId);
    final awayIndex = _teamIndex(_currentRequest.awayTeamId);
    if (homeIndex == null || awayIndex == null) return;
    final next = (_rematchIndex + 1) % _rematchCycle;
    final seed = deriveGameSeed(
      leagueSeed: _currentRequest.league.config.seed,
      homeIndex: homeIndex,
      awayIndex: awayIndex,
      rematchIndex: next,
    );
    setState(() {
      _rematchIndex = next;
      _seedCycleRepeated = next == 0;
      // Rematch preserves every management decision; only the seed advances.
      _currentRequest = GameRequest(
        gameId: _currentRequest.gameId,
        league: _currentRequest.league,
        homeTeamId: _currentRequest.homeTeamId,
        awayTeamId: _currentRequest.awayTeamId,
        seed: seed,
        homeLineup: _currentRequest.homeLineup,
        awayLineup: _currentRequest.awayLineup,
        rotationPlan: _currentRequest.rotationPlan,
      );
      _phase = _GamePhase.loading;
      _result = null;
      _failure = null;
    });
    _startRun();
  }

  void _returnToLeague() {
    if (widget.onReturn != null) {
      widget.onReturn!();
    } else {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  String _teamName(TeamId id) {
    for (final team in _currentRequest.league.teams) {
      if (team.id.value == id.value) return team.name;
    }
    return id.value;
  }

  String _describeFailure(Object error) {
    if (error is GameValidationException) {
      return [
        for (final issue in error.issues)
          '${issue.code.name}: ${issue.message}',
      ].join('\n');
    }
    return 'Unexpected error: $error';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Game Day')),
      body: switch (_phase) {
        _GamePhase.loading => _buildLoading(context),
        _GamePhase.failure => _buildFailure(context),
        _GamePhase.success => GameResultView(
          request: _currentRequest,
          result: _result!,
          seedCycleRepeated: _seedCycleRepeated,
          onRematch: widget.enableRematch ? _rematch : null,
          onReturnToLeague: _returnToLeague,
          returnButtonLabel: widget.returnButtonLabel,
        ),
      },
    );
  }

  Widget _buildLoading(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      key: const ValueKey('game-loading'),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              '${_teamName(_currentRequest.awayTeamId)} at '
              '${_teamName(_currentRequest.homeTeamId)}',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              'Simulating game · seed ${_currentRequest.seed}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFailure(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      key: const ValueKey('game-error'),
      padding: const EdgeInsets.all(24),
      children: [
        Icon(Icons.error_outline, size: 40, color: theme.colorScheme.error),
        const SizedBox(height: 12),
        Text('Game could not be simulated', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          _describeFailure(_failure!),
          key: const ValueKey('game-error-message'),
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 20),
        FilledButton(
          key: const ValueKey('retry-game'),
          onPressed: _retry,
          child: const Text('Retry'),
        ),
      ],
    );
  }
}

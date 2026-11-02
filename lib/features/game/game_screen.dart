import 'package:flutter/material.dart';
import 'package:simulation_core/simulation_core.dart';

import 'game_runner.dart';

/// Runs one confirmed game through the worker and renders exactly one state:
/// loading, failure or a minimal success summary.
///
/// Detailed scores, period tables and box scores belong to T024. This screen
/// never invents a result: the only data it shows comes from the returned
/// `GameResult`.
typedef GameRunner = Future<GameResult> Function(GameRequest request);

class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.request, this.runner = runGame});

  final GameRequest request;
  final GameRunner runner;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

enum _GamePhase { loading, success, failure }

class _GameScreenState extends State<GameScreen> {
  _GamePhase _phase = _GamePhase.loading;
  GameResult? _result;
  Object? _failure;
  bool _running = false;
  int _attempt = 0;

  @override
  void initState() {
    super.initState();
    _startRun();
  }

  Future<void> _startRun() async {
    if (_running) return;
    _running = true;
    final attempt = ++_attempt;
    try {
      final result = await widget.runner(widget.request);
      if (!mounted || attempt != _attempt) return;
      setState(() {
        _result = result;
        _phase = _GamePhase.success;
      });
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

  String _teamName(TeamId id) {
    for (final team in widget.request.league.teams) {
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
        _GamePhase.success => _buildSuccess(context),
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
              '${_teamName(widget.request.awayTeamId)} at '
              '${_teamName(widget.request.homeTeamId)}',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              'Simulating game · seed ${widget.request.seed}',
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

  Widget _buildSuccess(BuildContext context) {
    final theme = Theme.of(context);
    final result = _result!;
    return ListView(
      key: const ValueKey('game-success'),
      padding: const EdgeInsets.all(24),
      children: [
        Icon(
          Icons.check_circle_outline,
          size: 40,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(height: 12),
        Text('Game complete', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          '${_teamName(result.awayTeamId)} ${result.awayScore} – '
          '${result.homeScore} ${_teamName(result.homeTeamId)}',
          key: const ValueKey('game-score'),
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          '${result.periodsPlayed} periods · seed ${widget.request.seed}',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

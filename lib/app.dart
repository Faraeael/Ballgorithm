import 'package:flutter/material.dart';
import 'package:simulation_core/simulation_core.dart';

import 'features/game/game_screen.dart';
import 'features/league/league_screen.dart';
import 'features/season/franchise_select_screen.dart';
import 'features/season/season_controller.dart';
import 'features/season/season_dashboard_screen.dart';
import 'features/season/season_storage.dart';

class BasketballManagerApp extends StatefulWidget {
  const BasketballManagerApp({
    super.key,
    required this.league,
    this.storage,
    this.seasonMode,
    this.gameRunner,
  });

  final League league;
  final SeasonStorage? storage;
  final bool? seasonMode;
  final GameRunner? gameRunner;

  @override
  State<BasketballManagerApp> createState() => _BasketballManagerAppState();
}

class _BasketballManagerAppState extends State<BasketballManagerApp> {
  SeasonController? _controller;

  bool get _isSeasonActive => widget.seasonMode ?? (widget.storage != null);

  @override
  void initState() {
    super.initState();
    if (_isSeasonActive) {
      _controller = SeasonController(
        league: widget.league,
        storage: widget.storage ?? InMemorySeasonStorage(),
        gameRunner: widget.gameRunner,
      );
      _controller!.loadSeason();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Basketball Manager',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFB4541E)),
      ),
      home: _isSeasonActive
          ? _buildSeasonHome(context)
          : LeagueScreen(league: widget.league),
    );
  }

  Widget _buildSeasonHome(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller!,
      builder: (context, _) {
        if (_controller!.isLoading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (_controller!.errorMessage != null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Save Error')),
            body: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    size: 64,
                    color: Colors.orange,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Season Data Notice',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _controller!.errorMessage!,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () => _controller!.loadSeason(),
                    child: const Text('Retry Load'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: () => _controller!.resetSeason(),
                    child: const Text('Reset Save Data'),
                  ),
                ],
              ),
            ),
          );
        }

        if (!_controller!.hasActiveSeason) {
          return FranchiseSelectScreen(
            league: widget.league,
            controller: _controller!,
          );
        }

        return SeasonDashboardScreen(
          league: widget.league,
          controller: _controller!,
          runner: widget.gameRunner,
        );
      },
    );
  }
}

import 'package:flutter/material.dart';
import 'package:simulation_core/simulation_core.dart';
import 'features/career/career_controller.dart';
import 'features/career/career_setup_screens.dart';
import 'features/career/career_storage.dart';
import 'features/career/offseason_overview_screen.dart';
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
    this.careerStorage,
    this.careerController,
    this.seasonMode,
    this.gameRunner,
    this.seedProvider,
  });

  final League league;
  final SeasonStorage? storage;
  final GmCareerStorage? careerStorage;
  final GmCareerController? careerController;
  final bool? seasonMode;
  final GameRunner? gameRunner;
  final CareerSeedProvider? seedProvider;
  @override
  State<BasketballManagerApp> createState() => _BasketballManagerAppState();
}

class _BasketballManagerAppState extends State<BasketballManagerApp> {
  SeasonController? _controller;
  GmCareerController? _careerController;
  bool _showFranchiseSelect = false;

  bool get _isSeasonActive => widget.seasonMode ?? (widget.storage != null);
  @override
  void initState() {
    super.initState();
    _careerController =
        widget.careerController ??
        GmCareerController(
          storage: widget.careerStorage ?? InMemoryGmCareerStorage(),
        );
    _careerController!.loadCareer();

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
    if (widget.careerController == null) {
      final controller = _careerController!;
      controller.commandsSettled.then((_) => controller.dispose());
    }
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
      listenable: Listenable.merge([_controller!, _careerController!]),
      builder: (context, _) {
        if (_controller!.isLoading ||
            (_careerController!.isLoading && !_careerController!.hasCareer)) {
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

        // M007 playable-season takes priority if active
        if (_controller!.hasActiveSeason) {
          return SeasonDashboardScreen(
            league: widget.league,
            controller: _controller!,
            runner: widget.gameRunner,
          );
        }

        // If GM Career save is active and user has not navigated out to franchise select
        if (_careerController!.hasCareer && !_showFranchiseSelect) {
          return GmOffseasonOverviewScreen(
            controller: _careerController!,
            onExit: () {
              setState(() {
                _showFranchiseSelect = true;
              });
            },
          );
        }

        return FranchiseSelectScreen(
          league: widget.league,
          controller: _controller!,
          careerController: _careerController,
          careerStorage: widget.careerStorage ?? _careerController!.storage,
          seedProvider: widget.seedProvider ?? defaultCareerSeedProvider,
          onResumeCareer: () {
            setState(() {
              _showFranchiseSelect = false;
            });
          },
        );
      },
    );
  }
}

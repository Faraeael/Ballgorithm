import 'package:flutter/material.dart';
import 'package:simulation_core/simulation_core.dart';

import '../career/career_controller.dart';
import '../career/career_setup_screens.dart';
import '../career/career_storage.dart';
import '../career/offseason_overview_screen.dart';
import '../game/game_setup_screen.dart';
import '../game/game_screen.dart';
import 'season_controller.dart';

class FranchiseSelectScreen extends StatefulWidget {
  const FranchiseSelectScreen({
    super.key,
    required this.league,
    required this.controller,
    this.careerController,
    this.careerStorage,
    this.seedProvider = defaultCareerSeedProvider,
    this.onResumeCareer,
  });

  final League league;
  final SeasonController controller;
  final GmCareerController? careerController;
  final GmCareerStorage? careerStorage;
  final CareerSeedProvider seedProvider;
  final VoidCallback? onResumeCareer;
  @override
  State<FranchiseSelectScreen> createState() => _FranchiseSelectScreenState();
}

class _FranchiseSelectScreenState extends State<FranchiseSelectScreen> {
  TeamId? _selectedId;
  bool _hasSavedCareer = false;
  GmCareer? _savedCareer;
  String? _careerSaveError;
  bool _resumingCareer = false;

  bool get _hasCareer =>
      _hasSavedCareer || (widget.careerController?.hasCareer ?? false);
  GmCareer? get _activeCareer =>
      widget.careerController?.career ?? _savedCareer;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.league.teams.first.id;
    if (widget.careerController?.hasCareer ?? false) {
      _hasSavedCareer = true;
      _savedCareer = widget.careerController!.career;
    }
    _checkCareerSave();
  }

  Future<void> _checkCareerSave() async {
    final storage = widget.careerController?.storage ?? widget.careerStorage;
    if (storage == null) return;
    try {
      final hasSave = await storage.hasSave();
      final raw = hasSave ? await storage.read() : null;
      final career = raw == null ? null : GmCareerCodec.decode(raw);
      if (!mounted) return;
      setState(() {
        _hasSavedCareer = hasSave;
        _savedCareer = career;
        _careerSaveError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _hasSavedCareer = true;
        _savedCareer = null;
        _careerSaveError =
            'Failed to load GM Career: $error. Save file preserved.';
      });
    }
  }

  Future<void> _handleResumeCareer() async {
    if (_resumingCareer) return;
    setState(() => _resumingCareer = true);
    try {
      final controller = widget.careerController;
      final storage = controller?.storage ?? widget.careerStorage;
      if (controller != null) {
        if (!controller.hasCareer) {
          await controller.loadCareer();
          if (controller.errorMessage != null) {
            throw StateError(controller.errorMessage!);
          }
          if (!controller.hasCareer) {
            throw const FormatException('Career save is missing or empty.');
          }
        }
        if (!mounted) return;
        if (widget.onResumeCareer != null) {
          widget.onResumeCareer!();
          return;
        }
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => GmOffseasonOverviewScreen(controller: controller),
          ),
        );
      } else {
        if (storage == null) {
          throw StateError('No GM Career storage is available.');
        }
        if (!mounted) return;
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => GmOffseasonOverviewRoute(storage: storage),
          ),
        );
      }
      if (mounted) await _checkCareerSave();
    } catch (error) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Save Error'),
          content: Text(
            'Failed to load GM Career: $error\n\nThe save file has been preserved.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _resumingCareer = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ballgorithm'),
        actions: [
          if (_hasCareer)
            IconButton(
              key: const ValueKey('resume-career-button'),
              tooltip: 'Resume GM Career',
              icon: const Icon(Icons.history_edu),
              onPressed: _resumingCareer ? null : _handleResumeCareer,
            ),
          TextButton(
            key: const ValueKey('open-career-preview'),
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => CareerSelectTeamScreen(
                    seedProvider: widget.seedProvider,
                    careerStorage: widget.careerStorage,
                    careerController: widget.careerController,
                  ),
                ),
              );
              if (mounted) {
                _checkCareerSave();
              }
            },
            child: const Text('GM Career'),
          ),
          IconButton(
            key: const ValueKey('open-exhibition'),
            tooltip: 'Exhibition',
            icon: const Icon(Icons.sports_basketball_outlined),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => GameSetupScreen(
                    league: widget.league,
                    onConfirm: (request) => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => GameScreen(request: request),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          if (_hasCareer)
            Padding(
              padding: const EdgeInsets.fromLTRB(16.0, 4.0, 16.0, 4.0),
              child: Card(
                color: theme.colorScheme.tertiaryContainer,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12.0,
                    vertical: 6.0,
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.sports_basketball, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _activeCareer != null
                                  ? 'Resume GM Career: ${_activeCareer!.userTeam.name}'
                                  : 'Resume GM Career',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              _careerSaveError ??
                                  (_activeCareer != null
                                      ? 'Year ${_activeCareer!.currentYear} • ${_activeCareer!.phase.displayName}'
                                      : 'Saved career data found'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        key: const ValueKey('resume-career-card-button'),
                        style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                        onPressed: _resumingCareer ? null : _handleResumeCareer,
                        child: const Text('Resume'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Select Your Franchise',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Choose one of 8 teams to manage through a 14-game regular season.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              itemCount: widget.league.teams.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final team = widget.league.teams[index];
                final isSelected = team.id == _selectedId;

                return ListTile(
                  key: ValueKey('team-card-${team.id.value}'),
                  selected: isSelected,
                  selectedTileColor: theme.colorScheme.primaryContainer
                      .withValues(alpha: 0.3),
                  leading: CircleAvatar(
                    backgroundColor: isSelected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.surfaceContainerHighest,
                    foregroundColor: isSelected
                        ? theme.colorScheme.onPrimary
                        : theme.colorScheme.onSurface,
                    child: Text(
                      team.abbreviation,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  title: Text(
                    team.name,
                    style: TextStyle(
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                  subtitle: Text(
                    '${team.players.length} Players',
                    style: theme.textTheme.bodySmall,
                  ),
                  trailing: isSelected
                      ? Icon(
                          Icons.check_circle,
                          color: theme.colorScheme.primary,
                        )
                      : const Icon(Icons.radio_button_unchecked),
                  onTap: () {
                    setState(() {
                      _selectedId = team.id;
                    });
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                key: const ValueKey('start-season-button'),
                onPressed: _selectedId == null
                    ? null
                    : () async {
                        await widget.controller.startNewSeason(_selectedId!);
                      },
                child: const Text('Start Season'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

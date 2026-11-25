import 'package:flutter/material.dart';
import 'package:simulation_core/simulation_core.dart';

import '../../theme/hardwood_command_theme.dart';
import '../game/game_runner.dart';
import '../season/franchise_select_screen.dart';
import '../season/season_controller.dart';
import 'career_controller.dart';
import 'career_setup_screens.dart';
import 'career_storage.dart';
import 'career_ui_labels.dart';
import 'widgets/hardwood_components.dart';

/// Primary launch menu prioritizing the 30-team GM Career while preserving
/// Classic 8-Team Season (M007) as a secondary entry.
class MainMenuScreen extends StatefulWidget {
  const MainMenuScreen({
    super.key,
    required this.league,
    required this.seasonController,
    required this.careerController,
    required this.careerStorage,
    this.gameRunner,
    this.seedProvider = defaultCareerSeedProvider,
    required this.onContinueCareer,
  });

  final League league;
  final SeasonController seasonController;
  final GmCareerController careerController;
  final GmCareerStorage careerStorage;
  final GameRunner? gameRunner;
  final CareerSeedProvider seedProvider;
  final VoidCallback onContinueCareer;

  @override
  State<MainMenuScreen> createState() => _MainMenuScreenState();
}

class _MainMenuScreenState extends State<MainMenuScreen> {
  String? _localStorageError;
  bool _checkingNewCareer = false;

  Future<void> _handleNewCareer(BuildContext context) async {
    if (_checkingNewCareer) return;
    setState(() {
      _checkingNewCareer = true;
      _localStorageError = null;
    });
    try {
      final hasSave = await widget.careerStorage.hasSave();
      if (!context.mounted) return;
      setState(() => _checkingNewCareer = false);
      if (hasSave || widget.careerController.hasCareer) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Replace Existing Career?'),
            content: const Text(
              'A GM Career save already exists in local storage. Only one '
              'career slot is currently supported.\n\n'
              'Continuing to New GM Career will overwrite your existing save '
              'when you confirm creation.',
            ),
            actions: [
              TextButton(
                key: const ValueKey('cancel-new-career-replace'),
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                key: const ValueKey('confirm-new-career-replace'),
                style: FilledButton.styleFrom(
                  backgroundColor: context.tokens.statusDanger,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Continue to Setup'),
              ),
            ],
          ),
        );
        if (confirmed != true || !context.mounted) return;
      }

      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => CareerSelectTeamScreen(
            seedProvider: widget.seedProvider,
            careerStorage: widget.careerStorage,
            careerController: widget.careerController,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _localStorageError =
            'Cannot verify existing career storage safely: $error';
      });
    } finally {
      if (mounted) {
        setState(() => _checkingNewCareer = false);
      }
    }
  }

  void _openClassicMode(BuildContext context) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => FranchiseSelectScreen(
          league: widget.league,
          controller: widget.seasonController,
          careerController: widget.careerController,
          careerStorage: widget.careerStorage,
          seedProvider: widget.seedProvider,
          onResumeCareer: () {
            Navigator.of(context).pop();
            widget.onContinueCareer();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ListenableBuilder(
      listenable: widget.careerController,
      builder: (context, _) {
        final career = widget.careerController.career;
        final error =
            _localStorageError ?? widget.careerController.errorMessage;
        final hasCareer = career != null;

        return Scaffold(
          backgroundColor: t.bgCanvas,
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(t.space400),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(height: t.space300),
                      // Brand Identity Header
                      Container(
                        padding: EdgeInsets.all(t.space400),
                        decoration: BoxDecoration(
                          color: t.bgSurface,
                          borderRadius: BorderRadius.circular(t.radiusLg),
                          border: Border.all(color: t.borderSubtle),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const FranchiseCrestBadge(
                                  abbreviation: 'BG',
                                  size: 46,
                                ),
                                SizedBox(width: t.space300),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'BALLGORITHM',
                                        style: TextStyle(
                                          color: t.textPrimary,
                                          fontSize: 22,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.8,
                                        ),
                                      ),
                                      SizedBox(height: 2),
                                      Text(
                                        'Hardwood Command • 30-Team GM Career',
                                        style: TextStyle(
                                          color: t.accentPrimary,
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: t.space300),
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: t.space200,
                                vertical: t.space100,
                              ),
                              decoration: BoxDecoration(
                                color: t.statusSuccessBg,
                                borderRadius: BorderRadius.circular(
                                  t.radiusPill,
                                ),
                                border: Border.all(
                                  color: t.statusSuccess.withValues(alpha: 0.4),
                                ),
                              ),
                              child: Text(
                                'OFFLINE LOCAL SAVE',
                                style: TextStyle(
                                  color: t.statusSuccessFg,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: t.space400),

                      // Visible Persistence / Recovery Error Banner
                      if (error != null) ...[
                        Container(
                          key: const ValueKey('main-menu-storage-error'),
                          padding: EdgeInsets.all(t.space300),
                          decoration: BoxDecoration(
                            color: t.statusDangerBg,
                            borderRadius: BorderRadius.circular(t.radiusMd),
                            border: Border.all(color: t.statusDanger),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.error_outline,
                                    color: t.statusDangerFg,
                                    size: 20,
                                  ),
                                  SizedBox(width: t.space200),
                                  Expanded(
                                    child: Text(
                                      'Save Storage Notice',
                                      style: TextStyle(
                                        color: t.statusDangerFg,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: t.space200),
                              Text(
                                error,
                                style: TextStyle(
                                  color: t.textPrimary,
                                  fontSize: 13,
                                ),
                              ),
                              SizedBox(height: t.space300),
                              HardwoodSecondaryButton(
                                key: const ValueKey('main-menu-retry-load'),
                                label: 'Retry Load Saved Career',
                                icon: Icons.refresh,
                                onPressed: widget.careerController.isLoading
                                    ? null
                                    : () {
                                        setState(
                                          () => _localStorageError = null,
                                        );
                                        widget.careerController.loadCareer();
                                      },
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: t.space400),
                      ],

                      // Primary 30-Team GM Career Entry
                      if (hasCareer) ...[
                        Container(
                          padding: EdgeInsets.all(t.space400),
                          decoration: BoxDecoration(
                            color: t.bgSurface,
                            borderRadius: BorderRadius.circular(t.radiusLg),
                            border: Border.all(
                              color: t.borderActive,
                              width: 1.5,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'ACTIVE FRANCHISE SAVE',
                                style: TextStyle(
                                  color: t.accentPrimary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.7,
                                ),
                              ),
                              SizedBox(height: t.space200),
                              Row(
                                children: [
                                  FranchiseCrestBadge(
                                    abbreviation: career.userTeam.abbreviation,
                                    size: 40,
                                  ),
                                  SizedBox(width: t.space300),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          career.userTeam.name,
                                          style: TextStyle(
                                            color: t.textPrimary,
                                            fontSize: 16,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        SizedBox(height: 2),
                                        Text(
                                          _careerSummarySubtitle(career),
                                          style: TextStyle(
                                            color: t.textSecondary,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: t.space400),
                              HardwoodPrimaryCta(
                                key: const ValueKey(
                                  'continue-gm-career-button',
                                ),
                                label: 'Continue GM Career',
                                icon: Icons.play_arrow_rounded,
                                onPressed: widget.onContinueCareer,
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: t.space300),
                        HardwoodSecondaryButton(
                          key: const ValueKey('open-career-preview'),
                          label: _checkingNewCareer
                              ? 'Checking Local Save…'
                              : 'New GM Career',
                          icon: Icons.add_circle_outline,
                          onPressed: _checkingNewCareer
                              ? null
                              : () => _handleNewCareer(context),
                        ),
                      ] else ...[
                        HardwoodPrimaryCta(
                          key: const ValueKey('open-career-preview'),
                          label: 'New GM Career',
                          icon: Icons.add_circle_outline,
                          isBusy: _checkingNewCareer,
                          onPressed: _checkingNewCareer
                              ? null
                              : () => _handleNewCareer(context),
                        ),
                        SizedBox(height: t.space200),
                        Container(
                          padding: EdgeInsets.all(t.space300),
                          decoration: BoxDecoration(
                            color: t.bgSurface,
                            borderRadius: BorderRadius.circular(t.radiusMd),
                            border: Border.all(color: t.borderSubtle),
                          ),
                          child: Text(
                            'No active 30-team GM Career save found. Start a new '
                            'career to draft, sign free agents, and manage a '
                            'franchise across full 82-game seasons.',
                            style: TextStyle(
                              color: t.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],

                      SizedBox(height: t.space600),
                      Divider(color: t.borderSubtle),
                      SizedBox(height: t.space300),

                      // Secondary Entry: Classic Season
                      Text(
                        'OTHER MODES',
                        style: TextStyle(
                          color: t.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.7,
                        ),
                      ),
                      SizedBox(height: t.space200),
                      HardwoodSecondaryButton(
                        key: const ValueKey('open-classic-mode-button'),
                        label: 'Classic Season',
                        icon: Icons.sports_basketball_outlined,
                        onPressed: () => _openClassicMode(context),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '8-team single-season mode',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: t.textMuted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String _careerSummarySubtitle(GmCareer career) {
    final phase = CareerUiLabels.phaseName(career.phase);
    final season = career.regularSeasonState;
    if (season == null) {
      return 'Season ${career.currentYear} • $phase';
    }
    final ranked = season.standings.ranked;
    final idx = ranked.indexWhere(
      (row) => row.teamId == career.userFranchiseId,
    );
    if (idx == -1) {
      return 'Season ${career.currentYear} • $phase';
    }
    final row = ranked[idx];
    return 'Season ${career.currentYear} • $phase • ${row.wins}–${row.losses} (#${idx + 1} of 30)';
  }
}

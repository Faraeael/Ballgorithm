import 'package:flutter/material.dart';
import 'package:simulation_core/simulation_core.dart';

import '../../theme/hardwood_command_theme.dart';
import 'career_career_tab.dart';
import 'career_controller.dart';
import 'career_home_screen.dart';
import 'career_league_tab.dart';
import 'career_market_tab.dart';
import 'career_team_tab.dart';
import 'career_ui_labels.dart';
import 'widgets/hardwood_components.dart';

/// Persistent 5-tab navigation shell (`HOME | TEAM | LEAGUE | MARKET | CAREER`)
/// across all four GM Career phases (`openingOffseason`, `regularSeason`,
/// `playIn`, `playoffs`).
class CareerShellScaffold extends StatefulWidget {
  const CareerShellScaffold({
    super.key,
    required this.controller,
    required this.onReturnToMainMenu,
    this.initialTabIndex = 0,
  });

  final GmCareerController controller;
  final VoidCallback onReturnToMainMenu;
  final int initialTabIndex;

  @override
  State<CareerShellScaffold> createState() => _CareerShellScaffoldState();
}

class _CareerShellScaffoldState extends State<CareerShellScaffold> {
  late int _selectedIndex;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialTabIndex.clamp(0, 4);
  }

  void _selectTab(int index) {
    if (_selectedIndex == index) return;
    setState(() => _selectedIndex = index);
  }

  Future<void> _openCareerMenu(BuildContext context, GmCareer career) async {
    final t = context.tokens;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: t.bgSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(t.radiusLg)),
        side: BorderSide(color: t.borderSubtle),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: EdgeInsets.all(t.space400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${career.userTeam.name} • Season ${career.currentYear}',
                style: TextStyle(
                  color: t.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: t.space100),
              Text(
                'Phase: ${CareerUiLabels.phaseName(career.phase)} • Offline Local Save',
                style: TextStyle(color: t.textSecondary, fontSize: 13),
              ),
              SizedBox(height: t.space400),
              HardwoodSecondaryButton(
                key: const ValueKey('return-to-main-menu-button'),
                label: 'Return to Main Menu',
                icon: Icons.home_outlined,
                onPressed:
                    widget.controller.isLoading ||
                        widget.controller.isBatchSimulating
                    ? null
                    : () {
                        Navigator.of(sheetContext).pop();
                        widget.onReturnToMainMenu();
                      },
              ),
              SizedBox(height: t.space200),
              HardwoodSecondaryButton(
                label: 'Close Menu',
                onPressed: () => Navigator.of(sheetContext).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_selectedIndex != 0) {
          _selectTab(0);
        } else if (!widget.controller.isLoading &&
            !widget.controller.isBatchSimulating) {
          widget.onReturnToMainMenu();
        }
      },
      child: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          final career = widget.controller.career;
          if (career == null) {
            return Scaffold(
              backgroundColor: t.bgCanvas,
              body: const Center(child: CircularProgressIndicator()),
            );
          }

          final body = IndexedStack(
            index: _selectedIndex,
            children: [
              CareerHomeScreen(
                controller: widget.controller,
                onSelectTab: _selectTab,
              ),
              CareerTeamTab(controller: widget.controller),
              CareerLeagueTab(controller: widget.controller),
              CareerMarketTab(controller: widget.controller),
              CareerCareerTab(
                controller: widget.controller,
                onReturnToMainMenu: () {
                  if (widget.controller.isLoading ||
                      widget.controller.isBatchSimulating) {
                    return;
                  }
                  widget.onReturnToMainMenu();
                },
              ),
            ],
          );

          return LayoutBuilder(
            builder: (context, constraints) {
              final useRail = constraints.maxWidth >= 600;
              return Scaffold(
                backgroundColor: t.bgCanvas,
                body: SafeArea(
                  bottom: !useRail,
                  child: Column(
                    children: [
                      _buildFranchiseHeader(context, t, career),
                      Expanded(
                        child: useRail
                            ? Row(
                                children: [
                                  _buildNavigationRail(
                                    t,
                                    extended: constraints.maxWidth >= 960,
                                  ),
                                  VerticalDivider(
                                    width: 1,
                                    color: t.borderSubtle,
                                  ),
                                  Expanded(child: body),
                                ],
                              )
                            : body,
                      ),
                    ],
                  ),
                ),
                bottomNavigationBar: useRail ? null : _buildBottomNav(t),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildFranchiseHeader(
    BuildContext context,
    HardwoodCommandTokens t,
    GmCareer career,
  ) {
    final team = career.userTeam;
    final phaseLabel = CareerUiLabels.phaseName(career.phase);
    final season = career.regularSeasonState;
    String? recordRankText;
    if (season != null) {
      final ranked = season.standings.ranked;
      final idx = ranked.indexWhere(
        (row) => row.teamId == career.userFranchiseId,
      );
      if (idx != -1) {
        final row = ranked[idx];
        recordRankText = '${row.wins}–${row.losses} • #${idx + 1} of 30';
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: t.bgGlassHeader,
        border: Border(bottom: BorderSide(color: t.borderSubtle)),
      ),
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 4,
            child: ColoredBox(color: t.teamPrimary),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
            child: Row(
              children: [
                FranchiseCrestBadge(abbreviation: team.abbreviation, size: 38),
                SizedBox(width: t.space200),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        team.name.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: t.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.35,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Wrap(
                        spacing: 6,
                        children: [
                          Text(
                            'Season ${career.currentYear} • $phaseLabel',
                            style: TextStyle(
                              color: t.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (recordRankText != null)
                            Text(
                              recordRankText,
                              style: TextStyle(
                                color: t.accentPrimary,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                AppPressable(
                  key: const ValueKey('career-shell-menu-button'),
                  semanticLabel: 'Open career menu',
                  onPressed:
                      widget.controller.isLoading ||
                          widget.controller.isBatchSimulating
                      ? null
                      : () => _openCareerMenu(context, career),
                  borderRadius: BorderRadius.circular(t.radiusMd),
                  child: Container(
                    width: t.touchMin,
                    height: t.touchMin,
                    decoration: BoxDecoration(
                      color: t.bgElevated,
                      borderRadius: BorderRadius.circular(t.radiusMd),
                      border: Border.all(color: t.borderSubtle),
                    ),
                    child: Icon(Icons.menu_rounded, color: t.textPrimary),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static const _destinations = <({String label, IconData icon, String key})>[
    (label: 'HOME', icon: Icons.dashboard_rounded, key: 'nav-tab-home'),
    (label: 'TEAM', icon: Icons.groups_rounded, key: 'nav-tab-team'),
    (label: 'LEAGUE', icon: Icons.leaderboard_rounded, key: 'nav-tab-league'),
    (label: 'MARKET', icon: Icons.storefront_rounded, key: 'nav-tab-market'),
    (label: 'CAREER', icon: Icons.emoji_events_rounded, key: 'nav-tab-career'),
  ];

  Widget _buildBottomNav(HardwoodCommandTokens t) {
    return Container(
      decoration: BoxDecoration(
        color: t.bgGlassHeader,
        border: Border(top: BorderSide(color: t.borderSubtle)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              for (var i = 0; i < _destinations.length; i++)
                Expanded(
                  child: AppPressable(
                    key: ValueKey(_destinations[i].key),
                    semanticLabel: _destinations[i].label,
                    minHeight: 48,
                    onPressed: () => _selectTab(i),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        if (_selectedIndex == i)
                          Positioned(
                            top: 0,
                            left: 12,
                            right: 12,
                            height: 3,
                            child: Container(
                              decoration: BoxDecoration(
                                color: t.accentPrimary,
                                borderRadius: const BorderRadius.vertical(
                                  bottom: Radius.circular(3),
                                ),
                              ),
                            ),
                          ),
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _destinations[i].icon,
                              size: 20,
                              color: _selectedIndex == i
                                  ? t.accentPrimary
                                  : t.textSecondary,
                            ),
                            const SizedBox(height: 4),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                _destinations[i].label,
                                maxLines: 1,
                                style: TextStyle(
                                  color: _selectedIndex == i
                                      ? t.accentPrimary
                                      : t.textSecondary,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavigationRail(
    HardwoodCommandTokens t, {
    required bool extended,
  }) {
    return NavigationRail(
      backgroundColor: t.bgGlassHeader,
      selectedIndex: _selectedIndex,
      extended: extended,
      onDestinationSelected: _selectTab,
      selectedIconTheme: IconThemeData(color: t.accentPrimary),
      unselectedIconTheme: IconThemeData(color: t.textSecondary),
      selectedLabelTextStyle: TextStyle(
        color: t.accentPrimary,
        fontWeight: FontWeight.w800,
        fontSize: 12,
      ),
      unselectedLabelTextStyle: TextStyle(
        color: t.textSecondary,
        fontWeight: FontWeight.w600,
        fontSize: 12,
      ),
      destinations: [
        for (final dest in _destinations)
          NavigationRailDestination(
            icon: Icon(dest.icon, key: ValueKey(dest.key)),
            label: Text(dest.label),
          ),
      ],
    );
  }
}

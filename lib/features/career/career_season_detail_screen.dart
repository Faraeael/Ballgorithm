import 'package:flutter/material.dart';
import 'package:simulation_core/simulation_core.dart';

import '../../theme/hardwood_command_theme.dart';
import 'career_controller.dart';
import 'widgets/hardwood_components.dart';

/// Detailed view for a single completed [SeasonHistoryRecord], optionally
/// loading the verified [SeasonArchive] if present in local storage.
class CareerSeasonDetailScreen extends StatefulWidget {
  const CareerSeasonDetailScreen({
    super.key,
    required this.controller,
    required this.record,
    required this.teamsById,
    required this.userTeamId,
  });

  final GmCareerController controller;
  final SeasonHistoryRecord record;
  final Map<TeamId, Team> teamsById;
  final TeamId userTeamId;

  @override
  State<CareerSeasonDetailScreen> createState() =>
      _CareerSeasonDetailScreenState();
}

class _CareerSeasonDetailScreenState extends State<CareerSeasonDetailScreen> {
  SeasonArchive? _archive;
  String? _archiveNote;
  bool _loadingArchive = true;

  @override
  void initState() {
    super.initState();
    _loadArchive();
  }

  Future<void> _loadArchive() async {
    try {
      final archive = await widget.controller.loadSeasonArchive(
        widget.record.seasonYear,
      );
      if (!mounted) return;
      setState(() {
        _archive = archive;
        _loadingArchive = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _archiveNote =
            'Compact season summary loaded. Full 1,230-game archive is not '
            'present for this save.';
        _loadingArchive = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final record = widget.record;
    final champTeam = widget.teamsById[record.championTeamId];
    final userWon = record.championTeamId == widget.userTeamId;
    final userStanding = record.regularSeasonStandings
        .cast<SeasonStandingSummary?>()
        .firstWhere((s) => s?.teamId == widget.userTeamId, orElse: () => null);

    return Scaffold(
      key: ValueKey('career-season-detail-${record.seasonYear}'),
      backgroundColor: t.bgCanvas,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context, t, record, champTeam),
            Expanded(
              child: ListView(
                padding: EdgeInsets.all(t.space300),
                children: [
                  // Champion & User Summary
                  _card(
                    t,
                    title: 'CHAMPIONSHIP & FRANCHISE OUTCOME',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.emoji_events_rounded,
                              color: userWon
                                  ? t.accentPrimary
                                  : t.accentSecondary,
                              size: 24,
                            ),
                            SizedBox(width: t.space200),
                            Expanded(
                              child: Text(
                                champTeam == null
                                    ? record.championTeamId.value
                                    : '${champTeam.name} (${champTeam.abbreviation})',
                                style: TextStyle(
                                  color: userWon
                                      ? t.accentPrimary
                                      : t.textPrimary,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (userStanding != null) ...[
                          SizedBox(height: t.space200),
                          Text(
                            'Your Franchise: ${userStanding.wins}–${userStanding.losses} '
                            '(#${userStanding.rank} of 30) • '
                            '${describePlayoffOutcome(record, widget.userTeamId)}',
                            style: TextStyle(
                              color: t.textSecondary,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                        SizedBox(height: t.space200),
                        if (_loadingArchive)
                          Text(
                            'Verifying season archive…',
                            style: TextStyle(
                              color: t.textMuted,
                              fontSize: 12.5,
                            ),
                          )
                        else if (_archive != null)
                          Text(
                            'Verified Archive: ${_archive!.regularSeasonState.completedGames} '
                            'regular-season games • Play-In (${_archive!.playInState.gameResults.length} games) • '
                            'Playoffs (${_archive!.playoffState.series.length} series)',
                            style: TextStyle(
                              color: t.statusSuccessFg,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          )
                        else if (_archiveNote != null)
                          Text(
                            _archiveNote!,
                            style: TextStyle(
                              color: t.textMuted,
                              fontSize: 12.5,
                            ),
                          ),
                      ],
                    ),
                  ),
                  SizedBox(height: t.space300),

                  // Play-In Outcomes
                  _card(
                    t,
                    title: 'PLAY-IN QUALIFIERS',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _rowLine(
                          t,
                          'Seed #15 Qualifier',
                          _teamName(record.playInOutcome.seed15TeamId),
                        ),
                        _rowLine(
                          t,
                          'Seed #16 Qualifier',
                          _teamName(record.playInOutcome.seed16TeamId),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: t.space300),

                  // Playoff Series Results
                  _card(
                    t,
                    title:
                        'PLAYOFF SERIES RESULTS (${record.playoffSeries.length})',
                    child: Column(
                      children: [
                        for (final series in record.playoffSeries)
                          _seriesRow(t, series),
                      ],
                    ),
                  ),
                  SizedBox(height: t.space300),

                  // Final Regular-Season Standings (All 30)
                  _card(
                    t,
                    title: 'REGULAR SEASON STANDINGS (30 TEAMS)',
                    child: Column(
                      children: [
                        for (final row in record.regularSeasonStandings)
                          _standingRow(t, row),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    HardwoodCommandTokens t,
    SeasonHistoryRecord record,
    Team? champTeam,
  ) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        t.space300,
        t.space200,
        t.space300,
        t.space300,
      ),
      decoration: BoxDecoration(
        color: t.bgGlassHeader,
        border: Border(bottom: BorderSide(color: t.borderSubtle)),
      ),
      child: Row(
        children: [
          AppPressable(
            key: const ValueKey('season-detail-back'),
            minWidth: t.touchMin,
            minHeight: t.touchMin,
            semanticLabel: 'Back',
            onPressed: () => Navigator.of(context).pop(),
            child: Container(
              width: t.touchMin,
              height: t.touchMin,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: t.bgElevated,
                borderRadius: BorderRadius.circular(t.radiusMd),
                border: Border.all(color: t.borderSubtle),
              ),
              child: Icon(
                Icons.arrow_back_rounded,
                color: t.textPrimary,
                size: 20,
              ),
            ),
          ),
          SizedBox(width: t.space300),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Season ${record.seasonYear} Archive',
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  'Champion: ${champTeam?.name ?? record.championTeamId.value}',
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
    );
  }

  String _teamName(TeamId id) {
    final team = widget.teamsById[id];
    return team == null ? id.value : '${team.abbreviation} • ${team.name}';
  }

  Widget _seriesRow(HardwoodCommandTokens t, PlayoffSeriesSummary series) {
    final involvesUser =
        series.firstTeamId == widget.userTeamId ||
        series.secondTeamId == widget.userTeamId;
    final first =
        widget.teamsById[series.firstTeamId]?.abbreviation ??
        series.firstTeamId.value;
    final second =
        widget.teamsById[series.secondTeamId]?.abbreviation ??
        series.secondTeamId.value;
    final winner =
        widget.teamsById[series.winnerTeamId]?.abbreviation ??
        series.winnerTeamId.value;

    return Container(
      margin: EdgeInsets.only(bottom: t.space100),
      padding: EdgeInsets.symmetric(
        horizontal: t.space200,
        vertical: t.space200,
      ),
      decoration: BoxDecoration(
        color: involvesUser ? t.accentPrimaryTint : t.bgElevated,
        borderRadius: BorderRadius.circular(t.radiusSm),
        border: Border.all(
          color: involvesUser ? t.borderActive : t.borderSubtle,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  series.round.displayName,
                  style: TextStyle(
                    color: t.textMuted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '$first vs $second (${series.firstTeamWins}–${series.secondTeamWins})',
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '$winner W',
            style: TextStyle(
              color: involvesUser ? t.accentPrimary : t.accentSecondaryFg,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _standingRow(HardwoodCommandTokens t, SeasonStandingSummary row) {
    final isUser = row.teamId == widget.userTeamId;
    final isChamp = row.teamId == widget.record.championTeamId;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: isUser ? t.accentPrimaryTint : Colors.transparent,
        borderRadius: BorderRadius.circular(t.radiusSm),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text(
              '#${row.rank}',
              style: TextStyle(
                color: isUser ? t.accentPrimary : t.textMuted,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(
            child: Text(
              '${_teamName(row.teamId)}${isChamp ? ' 🏆' : ''}',
              style: TextStyle(
                color: isUser ? t.accentPrimary : t.textPrimary,
                fontSize: 13.5,
                fontWeight: isUser ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
          Text(
            '${row.wins}–${row.losses}',
            style: TextStyle(
              color: isUser ? t.accentPrimary : t.textSecondary,
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _rowLine(HardwoodCommandTokens t, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: t.textSecondary, fontSize: 13.5),
            ),
          ),
          SizedBox(width: t.space200),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                color: t.textPrimary,
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(
    HardwoodCommandTokens t, {
    required String title,
    required Widget child,
  }) {
    return Container(
      padding: EdgeInsets.all(t.space300),
      decoration: BoxDecoration(
        color: t.bgSurface,
        borderRadius: BorderRadius.circular(t.radiusLg),
        border: Border.all(color: t.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: t.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
          SizedBox(height: t.space200),
          child,
        ],
      ),
    );
  }
}

/// Derives a concise, honest playoff outcome label for [teamId] from [record].
String describePlayoffOutcome(SeasonHistoryRecord record, TeamId teamId) {
  if (record.championTeamId == teamId) {
    return 'Champion';
  }
  PlayoffRound? furthest;
  for (final series in record.playoffSeries) {
    if (series.firstTeamId == teamId || series.secondTeamId == teamId) {
      if (furthest == null || series.round.index > furthest.index) {
        furthest = series.round;
      }
    }
  }
  if (furthest != null) {
    return furthest.displayName;
  }
  return 'Missed Playoffs';
}

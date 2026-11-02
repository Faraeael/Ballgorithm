import 'package:flutter/material.dart';
import 'package:simulation_core/simulation_core.dart';

import 'game_runner.dart';
import 'game_seed.dart';

/// Read-only results presentation for one completed game.
///
/// Every value here comes from the validated [GameResult]; nothing is
/// recomputed. Detailed layout polish and device-width acceptance belong to
/// T025.
class GameResultView extends StatelessWidget {
  const GameResultView({
    super.key,
    required this.request,
    required this.result,
    required this.seedCycleRepeated,
    required this.onRematch,
    required this.onReturnToLeague,
  });

  final GameRequest request;
  final GameResult result;

  /// True when the last rematch wrapped the 256-game seed cycle.
  final bool seedCycleRepeated;
  final VoidCallback onRematch;
  final VoidCallback onReturnToLeague;

  Team _team(TeamId id) =>
      request.league.teams.singleWhere((team) => team.id.value == id.value);

  Player _player(Team team, String playerId) =>
      team.players.singleWhere((player) => player.id.value == playerId);

  String _periodLabel(int period) =>
      period <= result.input.rules.periods ? 'Q$period' : 'OT${period - 4}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final home = _team(result.homeTeamId);
    final away = _team(result.awayTeamId);
    final winner = _team(result.winnerTeamId);
    final homeBox = result.boxScore.teams[home.id.value]!;
    final awayBox = result.boxScore.teams[away.id.value]!;

    return ListView(
      key: const ValueKey('game-success'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        _scoreboard(context, home: home, away: away, winner: winner),
        const SizedBox(height: 20),
        Text('Period scoring', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        _periodTable(theme, home: home, away: away),
        const SizedBox(height: 20),
        Text('Team statistics', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        _teamStatsTable(
          theme,
          home: home,
          away: away,
          homeBox: homeBox,
          awayBox: awayBox,
        ),
        const SizedBox(height: 20),
        Text(
          '${away.abbreviation} player box score',
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        _playerTable(theme, away),
        const SizedBox(height: 16),
        Text(
          '${home.abbreviation} player box score',
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        _playerTable(theme, home),
        const SizedBox(height: 24),
        _disclosures(context, theme),
        const SizedBox(height: 20),
        FilledButton(
          key: const ValueKey('rematch-game'),
          onPressed: onRematch,
          child: const Text('Rematch'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          key: const ValueKey('return-to-league'),
          onPressed: onReturnToLeague,
          child: const Text('Return to League'),
        ),
      ],
    );
  }

  Widget _scoreboard(
    BuildContext context, {
    required Team home,
    required Team away,
    required Team winner,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _scoreRow(
          theme,
          label: 'AWAY',
          team: away,
          score: result.awayScore,
          scoreKey: const ValueKey('result-score-away'),
        ),
        const SizedBox(height: 8),
        _scoreRow(
          theme,
          label: 'HOME',
          team: home,
          score: result.homeScore,
          scoreKey: const ValueKey('result-score-home'),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            Text(
              'Winner: ${winner.name}',
              key: const ValueKey('result-winner'),
              style: theme.textTheme.titleSmall,
            ),
            if (result.overtimes > 0)
              Text(
                '${result.overtimes} OT',
                key: const ValueKey('result-overtime'),
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            Text(
              'Seed ${describeGameSeed(request.seed)}',
              key: const ValueKey('result-seed'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            Text(
              '${result.periodsPlayed} periods',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _scoreRow(
    ThemeData theme, {
    required String label,
    required Team team,
    required int score,
    required Key scoreKey,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.labelSmall),
              Text(
                '${team.abbreviation} · ${team.name}',
                style: theme.textTheme.titleMedium,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        Text(
          '$score',
          key: scoreKey,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _periodTable(
    ThemeData theme, {
    required Team home,
    required Team away,
  }) {
    final periods = [
      for (var period = 1; period <= result.periodsPlayed; period++) period,
    ];
    Widget cell(String text, {Key? key, bool header = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Text(
        text,
        key: key,
        textAlign: header ? TextAlign.center : TextAlign.center,
        style: header ? theme.textTheme.labelSmall : theme.textTheme.bodyMedium,
      ),
    );

    return Table(
      key: const ValueKey('period-table'),
      columnWidths: {
        0: const FlexColumnWidth(2),
        for (var i = 1; i <= periods.length; i++) i: const FlexColumnWidth(1),
      },
      border: TableBorder(
        horizontalInside: BorderSide(
          color: theme.colorScheme.outlineVariant,
          width: 0.5,
        ),
      ),
      children: [
        TableRow(
          children: [
            cell('', header: true),
            for (final period in periods)
              cell(_periodLabel(period), header: true),
          ],
        ),
        for (final entry in {'away': away, 'home': home}.entries)
          TableRow(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  entry.value.abbreviation,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              for (final period in periods)
                cell(
                  '${result.boxScore.periodPoints[entry.value.id.value]![period] ?? 0}',
                  key: ValueKey(
                    'period-${entry.key}-${entry.value.id.value}-$period',
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Widget _teamStatsTable(
    ThemeData theme, {
    required Team home,
    required Team away,
    required TeamBoxScore homeBox,
    required TeamBoxScore awayBox,
  }) {
    final rows = <(String, String, String)>[
      ('PTS', '${homeBox.points}', '${awayBox.points}'),
      ('FG', '${homeBox.fgm}/${homeBox.fga}', '${awayBox.fgm}/${awayBox.fga}'),
      (
        '3PT',
        '${homeBox.threePm}/${homeBox.threePa}',
        '${awayBox.threePm}/${awayBox.threePa}',
      ),
      ('FT', '${homeBox.ftm}/${homeBox.fta}', '${awayBox.ftm}/${awayBox.fta}'),
      ('REB', '${homeBox.rebounds}', '${awayBox.rebounds}'),
      ('AST', '${homeBox.assists}', '${awayBox.assists}'),
      ('STL', '${homeBox.steals}', '${awayBox.steals}'),
      ('BLK', '${homeBox.blocks}', '${awayBox.blocks}'),
      ('TOV', '${homeBox.turnovers}', '${awayBox.turnovers}'),
      ('PF', '${homeBox.personalFouls}', '${awayBox.personalFouls}'),
    ];

    Widget text(String value, {Key? key, bool header = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
      child: Text(
        value,
        key: key,
        textAlign: TextAlign.center,
        style: header ? theme.textTheme.labelSmall : theme.textTheme.bodyMedium,
      ),
    );

    return Table(
      key: const ValueKey('team-stats-table'),
      columnWidths: const {
        0: FlexColumnWidth(2),
        1: FlexColumnWidth(2),
        2: FlexColumnWidth(2),
      },
      border: TableBorder(
        horizontalInside: BorderSide(
          color: theme.colorScheme.outlineVariant,
          width: 0.5,
        ),
      ),
      children: [
        TableRow(
          children: [
            text('', header: true),
            text(away.abbreviation, header: true),
            text(home.abbreviation, header: true),
          ],
        ),
        for (final row in rows)
          TableRow(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Text(row.$1, style: theme.textTheme.bodyMedium),
              ),
              text(
                row.$3,
                key: ValueKey('team-stat-${row.$1}-${away.id.value}'),
              ),
              text(
                row.$2,
                key: ValueKey('team-stat-${row.$1}-${home.id.value}'),
              ),
            ],
          ),
      ],
    );
  }

  Widget _playerTable(ThemeData theme, Team team) {
    final lineupIds = result.input.lineupFor(team.id).playerIds;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Swipe sideways for FT, REB, AST, STL, BLK, TOV and PF.',
          key: ValueKey('player-table-scroll-hint-${team.id.value}'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            key: ValueKey('player-table-${team.id.value}'),
            columnSpacing: 14,
            horizontalMargin: 4,
            headingRowHeight: 36,
            dataRowMinHeight: 34,
            dataRowMaxHeight: 40,
            columns: const [
              DataColumn(label: Text('Player')),
              DataColumn(label: Text('POS')),
              DataColumn(label: Text('PTS')),
              DataColumn(label: Text('FG')),
              DataColumn(label: Text('3PT')),
              DataColumn(label: Text('FT')),
              DataColumn(label: Text('REB')),
              DataColumn(label: Text('AST')),
              DataColumn(label: Text('STL')),
              DataColumn(label: Text('BLK')),
              DataColumn(label: Text('TOV')),
              DataColumn(label: Text('PF')),
            ],
            rows: [
              for (final playerId in lineupIds)
                _playerRow(theme, team, result.boxScore.players[playerId]!),
            ],
          ),
        ),
      ],
    );
  }

  DataRow _playerRow(ThemeData theme, Team team, PlayerBoxScore box) {
    final player = _player(team, box.playerId);
    Widget cell(String keySuffix, String text) =>
        Text(text, key: ValueKey('player-stat-${box.playerId}-$keySuffix'));
    return DataRow(
      key: ValueKey('player-row-${box.playerId}'),
      cells: [
        DataCell(
          Text(player.fullName, key: ValueKey('player-name-${box.playerId}')),
        ),
        DataCell(cell('POS', player.position.shortName)),
        DataCell(cell('PTS', '${box.points}')),
        DataCell(cell('FG', '${box.fgm}/${box.fga}')),
        DataCell(cell('3PT', '${box.threePm}/${box.threePa}')),
        DataCell(cell('FT', '${box.ftm}/${box.fta}')),
        DataCell(cell('REB', '${box.rebounds}')),
        DataCell(cell('AST', '${box.assists}')),
        DataCell(cell('STL', '${box.steals}')),
        DataCell(cell('BLK', '${box.blocks}')),
        DataCell(cell('TOV', '${box.turnovers}')),
        DataCell(cell('PF', '${box.personalFouls}')),
      ],
    );
  }

  Widget _disclosures(BuildContext context, ThemeData theme) {
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Each team fields one fixed five-player lineup for the whole game. '
          'Minutes, substitutions, fatigue and foul-outs are not modelled, so '
          'per-player totals are whole-game totals, not per-minute rates. '
          'These results are a deterministic simulation, not a realism claim.',
          key: const ValueKey('disclosure-lineup'),
          style: muted,
        ),
        const SizedBox(height: 8),
        Text(
          'Rematch seeds repeat after 256 games for the same matchup.',
          key: const ValueKey('disclosure-rematch-cycle'),
          style: muted,
        ),
        if (seedCycleRepeated) ...[
          const SizedBox(height: 8),
          Text(
            'Seed cycle repeated: this game reuses the first seed of the '
            'matchup cycle.',
            key: const ValueKey('disclosure-cycle-repeated'),
            style: muted,
          ),
        ],
        if (request.seed == 0) ...[
          const SizedBox(height: 8),
          Text(
            'Seed 0 is normalised to 0x9E3779B9 by the simulation engine.',
            key: const ValueKey('disclosure-zero-seed'),
            style: muted,
          ),
        ],
      ],
    );
  }
}

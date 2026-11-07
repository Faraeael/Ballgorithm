import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:simulation_core/simulation_core.dart';

import 'game_runner.dart';
import 'game_seed.dart';
import 'participation_view.dart';

/// Game Day setup (M003 T022, extended in M005 T05).
///
/// Choose two distinct teams, the managed side, its starting five and the
/// playing-time plan. The screen produces a [GameRequest] with the derived
/// seed, both lineups and both validated plans, and hands it to [onConfirm].
/// It never runs a game, shows a score or invents a result, and it never
/// duplicates the core preset or validation mathematics.
class GameSetupScreen extends StatefulWidget {
  const GameSetupScreen({
    super.key,
    required this.league,
    required this.onConfirm,
  });

  final League league;
  final ValueChanged<GameRequest> onConfirm;

  @override
  State<GameSetupScreen> createState() => _GameSetupScreenState();
}

class _GameSetupScreenState extends State<GameSetupScreen> {
  static const int _fineSeconds = 10;

  Team? _homeTeam;
  Team? _awayTeam;
  bool _manageHome = true;
  CourtLineup? _managedLineup;
  RotationPreset _preset = RotationPreset.balanced;
  final Map<String, int> _customTargets = <String, int>{};
  String? _planError;

  GameRules get _rules => GameRules.standard;

  int get _cap => RotationPlan.regulationCap(_rules);

  int get _teamTotal => 5 * _cap;

  int? _indexOf(Team? team) {
    if (team == null) return null;
    final index = widget.league.teams.indexWhere(
      (candidate) => candidate.id.value == team.id.value,
    );
    return index < 0 ? null : index;
  }

  int? get _seed {
    final homeIndex = _indexOf(_homeTeam);
    final awayIndex = _indexOf(_awayTeam);
    if (homeIndex == null || awayIndex == null || homeIndex == awayIndex) {
      return null;
    }
    return deriveGameSeed(
      leagueSeed: widget.league.config.seed,
      homeIndex: homeIndex,
      awayIndex: awayIndex,
      rematchIndex: 0,
    );
  }

  bool get _matchupReady => _seed != null && _homeTeam != null;

  Team? get _managedTeam => _manageHome ? _homeTeam : _awayTeam;

  // --- Plan construction ---------------------------------------------------

  TeamRotationPlan _planFor(
    Team team,
    CourtLineup lineup,
    RotationPreset preset,
    Map<String, int>? custom,
  ) {
    final targets = preset == RotationPreset.custom
        ? <PlayerId, int>{
            for (final player in team.players)
              player.id: custom?[player.id.value] ?? 0,
          }
        : RotationPlan.expandPreset(
            preset: preset,
            team: team,
            lineup: lineup,
            rules: _rules,
          );
    return TeamRotationPlan.create(
      team: team,
      preset: preset,
      targets: [
        for (final player in team.players)
          RotationTarget(playerId: player.id, seconds: targets[player.id] ?? 0),
      ],
    );
  }

  Map<String, int> _presetTargetSeconds(Team team, CourtLineup lineup) {
    final preset = _preset == RotationPreset.custom
        ? RotationPreset.balanced
        : _preset;
    final targets = RotationPlan.expandPreset(
      preset: preset,
      team: team,
      lineup: lineup,
      rules: _rules,
    );
    return {for (final entry in targets.entries) entry.key.value: entry.value};
  }

  /// The managed team's current target vector, in exact integer seconds.
  Map<String, int> _managedTargets() {
    final team = _managedTeam;
    final lineup = _managedLineup;
    if (team == null || lineup == null) return const <String, int>{};
    if (_preset == RotationPreset.custom) return _customTargets;
    return _presetTargetSeconds(team, lineup);
  }

  RotationPlan? _buildPlan() {
    final home = _homeTeam;
    final away = _awayTeam;
    final managed = _managedTeam;
    final lineup = _managedLineup;
    if (home == null || away == null || managed == null || lineup == null) {
      return null;
    }
    final managedPlan = _planFor(
      managed,
      lineup,
      _preset,
      _preset == RotationPreset.custom ? _customTargets : null,
    );
    final opponentPlan = _planFor(
      _manageHome ? away : home,
      CourtLineup.defaultFor(_manageHome ? away : home),
      RotationPreset.balanced,
      null,
    );
    return RotationPlan(
      home: _manageHome ? managedPlan : opponentPlan,
      away: _manageHome ? opponentPlan : managedPlan,
    );
  }

  CourtLineup? get _homeLineup => _lineupFor(_manageHome, _homeTeam);

  CourtLineup? get _awayLineup => _lineupFor(!_manageHome, _awayTeam);

  CourtLineup? _lineupFor(bool managed, Team? team) {
    if (team == null) return null;
    if (managed) return _managedLineup ?? CourtLineup.defaultFor(team);
    return CourtLineup.defaultFor(team);
  }

  /// Validates the complete candidate input with the core validator, so the UI
  /// never invents a rule the engine would reject.
  void _revalidate() {
    final plan = _buildPlan();
    final home = _homeTeam;
    final away = _awayTeam;
    final homeLineup = _homeLineup;
    final awayLineup = _awayLineup;
    final seed = _seed;
    _planError = null;
    if (plan == null ||
        home == null ||
        away == null ||
        homeLineup == null ||
        awayLineup == null ||
        seed == null) {
      return;
    }
    _refreshBudgetMessage();
    if (_planError != null) return;
    try {
      GameInput.create(
        gameId: '${home.id.value}-${away.id.value}-$seed',
        league: widget.league,
        homeTeamId: home.id,
        awayTeamId: away.id,
        homeLineup: homeLineup,
        awayLineup: awayLineup,
        seed: seed,
        rules: _rules,
        rotationPlan: plan,
      );
    } on GameValidationException catch (error) {
      _planError = [for (final issue in error.issues) issue.message].join(' ');
    } on DomainValidationException catch (error) {
      _planError = [for (final issue in error.issues) issue.message].join(' ');
    }
  }

  void _resetForMatchup({bool resetPreset = false}) {
    final team = _managedTeam;
    if (resetPreset && _preset == RotationPreset.custom) {
      _preset = RotationPreset.balanced;
    }
    _managedLineup = team == null ? null : CourtLineup.defaultFor(team);
    _customTargets.clear();
    if (team != null && _managedLineup != null) {
      if (_preset == RotationPreset.custom) {
        _customTargets.addAll(_presetTargetSeconds(team, _managedLineup!));
      }
    }
    _revalidate();
  }

  void _select({required bool home, required Team team}) {
    setState(() {
      final managedChanged = home == _manageHome;
      if (home) {
        _homeTeam = team;
      } else {
        _awayTeam = team;
      }
      if (managedChanged) {
        // The managed roster changed: rebuild its five and plan rather than
        // keeping stale player identities.
        _resetForMatchup();
      } else {
        _revalidate();
      }
    });
  }

  void _selectManaged(bool home) {
    if (!_matchupReady || home == _manageHome) return;
    setState(() {
      _manageHome = home;
      _resetForMatchup();
    });
  }

  void _selectStarter(int slotIndex, String playerId) {
    final team = _managedTeam;
    final lineup = _managedLineup;
    if (team == null || lineup == null) return;
    final players = [
      for (var index = 0; index < lineup.slots.length; index++)
        if (index == slotIndex)
          team.players.firstWhere((p) => p.id.value == playerId)
        else
          lineup.slots[index].player!,
    ];
    setState(() {
      _managedLineup = CourtLineup.create(
        team: team,
        slotOrderedPlayers: players,
      );
    });
    _revalidate();
  }

  void _selectPreset(RotationPreset preset) {
    final team = _managedTeam;
    final lineup = _managedLineup;
    setState(() {
      _customTargets.clear();
      if (preset == RotationPreset.custom && team != null && lineup != null) {
        // Starting point for custom editing: the allocation the user was just
        // shown. Resolve the active preset before switching, so custom never
        // silently inherits an unrelated preset's numbers.
        final source = _preset == RotationPreset.custom
            ? RotationPreset.balanced
            : _preset;
        final starting = RotationPlan.expandPreset(
          preset: source,
          team: team,
          lineup: lineup,
          rules: _rules,
        );
        _customTargets.addAll({
          for (final entry in starting.entries) entry.key.value: entry.value,
        });
      }
      _preset = preset;
      _revalidate();
    });
  }

  int get _customTotal =>
      _customTargets.values.fold<int>(0, (sum, value) => sum + value);

  int get _managedTotal =>
      _managedTargets().values.fold<int>(0, (sum, value) => sum + value);

  /// Highest value this player may take: the per-player cap and whatever the
  /// team budget still allows after the other players are counted.
  int _maximumAllowed(String playerId) {
    final current = _customTargets[playerId] ?? 0;
    final others = _customTotal - current;
    return math.min(_cap, _teamTotal - others);
  }

  /// Applies one exact integer-second value, rejecting any increase that would
  /// exceed the per-player cap or the team budget. The rejected proposal leaves
  /// the allocation untouched; no other player is adjusted.
  bool _setCustomTarget(String playerId, int seconds) {
    if (_preset != RotationPreset.custom) return false;
    final current = _customTargets[playerId] ?? 0;
    if (seconds == current) return false;
    final allowed = _maximumAllowed(playerId);
    if (seconds < 0 || seconds > allowed) return false;
    setState(() {
      _customTargets[playerId] = seconds;
      _refreshBudgetMessage();
    });
    return true;
  }

  /// Cheap budget/validation message refresh used on every slider tick, so a
  /// rapid drag or an interrupted gesture never leaves a stale error behind.
  /// Full core validation still runs on drag end and on fine adjustments.
  void _refreshBudgetMessage() {
    final team = _managedTeam;
    final lineup = _managedLineup;
    if (team == null || lineup == null) return;
    final targets = _managedTargets();
    final zeroStarters = [
      for (final slot in lineup.slots)
        if ((targets[slot.playerId.value] ?? 0) <= 0)
          team.players
              .firstWhere((player) => player.id.value == slot.playerId.value)
              .fullName,
    ];
    if (zeroStarters.isNotEmpty) {
      _planError =
          '${zeroStarters.join(', ')} '
          '${zeroStarters.length == 1 ? 'is a starter' : 'are starters'} '
          'and needs minutes. To give this player minutes, reduce another '
          "player's allocation first.";
      return;
    }
    final total = targets.values.fold<int>(0, (sum, value) => sum + value);
    _planError = total == _teamTotal
        ? null
        : 'Assign every minute before confirming. '
              '${formatMinutes(_teamTotal - total)} still available.';
  }

  void _fineAdjust(String playerId, int delta) {
    final current = _customTargets[playerId] ?? 0;
    if (_setCustomTarget(playerId, current + delta)) {
      _revalidate();
    }
  }

  bool get _canConfirm =>
      _seed != null &&
      _managedLineup != null &&
      _planError == null &&
      _managedTotal == _teamTotal;

  void _confirm() {
    final home = _homeTeam;
    final away = _awayTeam;
    final seed = _seed;
    final plan = _buildPlan();
    final homeLineup = _homeLineup;
    final awayLineup = _awayLineup;
    if (!_canConfirm ||
        home == null ||
        away == null ||
        seed == null ||
        plan == null ||
        homeLineup == null ||
        awayLineup == null) {
      return;
    }
    widget.onConfirm(
      GameRequest(
        league: widget.league,
        homeTeamId: home.id,
        awayTeamId: away.id,
        seed: seed,
        homeLineup: homeLineup,
        awayLineup: awayLineup,
        rotationPlan: plan,
      ),
    );
  }

  // --- Build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final home = _homeTeam;
    final away = _awayTeam;
    final seed = _seed;

    return Scaffold(
      appBar: AppBar(title: const Text('Game Day Setup')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text(widget.league.name, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(
            '${widget.league.teams.length} teams · seed '
            '${widget.league.config.seed}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          _TeamDropdown(
            label: 'Home team',
            fieldKey: const ValueKey('home-team-select'),
            optionKeyPrefix: 'home-option',
            teams: widget.league.teams,
            excludedTeamId: away?.id,
            selected: home,
            onChanged: (team) => _select(home: true, team: team),
          ),
          const SizedBox(height: 16),
          _TeamDropdown(
            label: 'Away team',
            fieldKey: const ValueKey('away-team-select'),
            optionKeyPrefix: 'away-option',
            teams: widget.league.teams,
            excludedTeamId: home?.id,
            selected: away,
            onChanged: (team) => _select(home: false, team: team),
          ),
          const SizedBox(height: 20),
          if (home != null && away != null)
            Text(
              '${away.name} at ${home.name}',
              key: const ValueKey('matchup-summary'),
              style: theme.textTheme.titleMedium,
            )
          else
            Text(
              'Select a home team and an away team.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          const SizedBox(height: 8),
          Text(
            seed == null
                ? 'Game seed: not set'
                : 'Game seed: ${describeGameSeed(seed)}',
            key: const ValueKey('derived-seed'),
            style: theme.textTheme.bodyMedium,
          ),
          if (_matchupReady) ...[
            const SizedBox(height: 24),
            _managedSection(theme, home!, away!),
            const SizedBox(height: 20),
            _startersSection(theme),
            const SizedBox(height: 20),
            _playingTimeSection(theme),
          ],
          const SizedBox(height: 24),
          if (_matchupReady && _planError != null) ...[
            Text(
              _planError!,
              key: const ValueKey('plan-error'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 12),
          ],
          FilledButton(
            key: const ValueKey('confirm-matchup'),
            onPressed: _canConfirm ? _confirm : null,
            child: const Text('Confirm matchup'),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(ThemeData theme, String title, String hint) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: theme.textTheme.titleSmall),
      const SizedBox(height: 2),
      Text(
        hint,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 8),
    ],
  );

  Widget _managedSection(ThemeData theme, Team home, Team away) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          theme,
          'Manage',
          'The opponent always uses its default five and a balanced plan.',
        ),
        SegmentedButton<bool>(
          segments: [
            ButtonSegment<bool>(
              value: true,
              label: Text(
                home.abbreviation,
                key: const ValueKey('managed-team-home'),
              ),
            ),
            ButtonSegment<bool>(
              value: false,
              label: Text(
                away.abbreviation,
                key: const ValueKey('managed-team-away'),
              ),
            ),
          ],
          selected: {_manageHome},
          onSelectionChanged: (selection) => _selectManaged(selection.first),
        ),
        const SizedBox(height: 6),
        Text(
          _manageHome ? home.name : away.name,
          key: const ValueKey('managed-team-name'),
          style: theme.textTheme.bodyMedium,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _startersSection(ThemeData theme) {
    final team = _managedTeam;
    final lineup = _managedLineup;
    if (team == null || lineup == null) return const SizedBox.shrink();
    final selected = {for (final slot in lineup.slots) slot.playerId.value};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          theme,
          'Starting five',
          'Slot position does not restrict a player; the five must be unique.',
        ),
        for (var index = 0; index < lineup.slots.length; index++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 36,
                  child: Text(
                    lineup.slots[index].slot.shortName,
                    style: theme.textTheme.labelLarge,
                  ),
                ),
                Expanded(
                  child: DropdownButton<String>(
                    key: ValueKey(
                      'starter-slot-${lineup.slots[index].slot.shortName.toLowerCase()}',
                    ),
                    isExpanded: true,
                    value: lineup.slots[index].playerId.value,
                    items: [
                      for (final player in team.players)
                        if (player.id.value ==
                                lineup.slots[index].playerId.value ||
                            !selected.contains(player.id.value))
                          DropdownMenuItem<String>(
                            key: ValueKey(
                              'starter-option-'
                              '${lineup.slots[index].slot.shortName.toLowerCase()}'
                              '-${player.id.value}',
                            ),
                            value: player.id.value,
                            child: Text(
                              '${player.fullName} · '
                              '${player.position.shortName}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _selectStarter(index, value));
                    },
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _playingTimeSection(ThemeData theme) {
    final team = _managedTeam;
    final lineup = _managedLineup;
    if (team == null || lineup == null) return const SizedBox.shrink();
    final targets = _managedTargets();
    final total = targets.values.fold<int>(0, (sum, value) => sum + value);
    final participants = _orderedPlayers(
      team,
      lineup,
    ).where((player) => (targets[player.id.value] ?? 0) > 0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          theme,
          'Playing time',
          'Targets are best-effort minutes, not guaranteed playing time.',
        ),
        SegmentedButton<RotationPreset>(
          segments: const [
            ButtonSegment<RotationPreset>(
              value: RotationPreset.balanced,
              label: Text('Balanced', key: ValueKey('preset-balanced')),
            ),
            ButtonSegment<RotationPreset>(
              value: RotationPreset.starterHeavy,
              label: Text(
                'Starter-heavy',
                key: ValueKey('preset-starterHeavy'),
              ),
            ),
            ButtonSegment<RotationPreset>(
              value: RotationPreset.custom,
              label: Text('Custom', key: ValueKey('preset-custom')),
            ),
          ],
          selected: {_preset},
          onSelectionChanged: (selection) => _selectPreset(selection.first),
        ),
        const SizedBox(height: 8),
        _budgetPanel(theme, total),
        if (_preset != RotationPreset.custom) ...[
          const SizedBox(height: 8),
          for (final player in participants)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      player.fullName,
                      style: theme.textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    formatMinutes(targets[player.id.value] ?? 0),
                    key: ValueKey('target-preview-${player.id.value}'),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
        ],
        if (_preset == RotationPreset.custom)
          Theme(
            data: theme.copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              key: const ValueKey('custom-editor'),
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: Text(
                'Minute allocation',
                style: theme.textTheme.bodyMedium,
              ),
              subtitle: Text(
                'Drag a slider to move minutes. The team budget is a hard '
                'limit of ${formatMinutes(_teamTotal)}.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              children: [
                for (final player in _orderedPlayers(team, lineup))
                  _customRow(theme, team, lineup, player, targets),
              ],
            ),
          ),
      ],
    );
  }

  List<Player> _orderedPlayers(Team team, CourtLineup lineup) {
    final byId = {for (final player in team.players) player.id.value: player};
    final ordered = <Player>[
      for (final slot in lineup.slots) byId[slot.playerId.value]!,
    ];
    final starters = {for (final slot in lineup.slots) slot.playerId.value};
    ordered.addAll([
      for (final player in team.players)
        if (!starters.contains(player.id.value)) player,
    ]);
    return ordered;
  }

  String _budgetLabel(int seconds) {
    final whole = seconds < 0 ? 0 : seconds;
    return '${(whole ~/ 60).toString().padLeft(2, '0')}:'
        '${(whole % 60).toString().padLeft(2, '0')}';
  }

  Widget _budgetPanel(ThemeData theme, int total) {
    final available = _teamTotal - total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Allocated: ${_budgetLabel(total)} / '
                '${_budgetLabel(_teamTotal)}',
                key: const ValueKey('budget-allocated'),
                style: theme.textTheme.bodyMedium,
              ),
            ),
            Text(
              'Available: ${_budgetLabel(available)}',
              key: const ValueKey('budget-available'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: available == 0
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        LinearProgressIndicator(
          key: const ValueKey('budget-progress'),
          value: (total / _teamTotal).clamp(0.0, 1.0),
          minHeight: 6,
          borderRadius: BorderRadius.circular(3),
        ),
        if (available == 0) ...[
          const SizedBox(height: 6),
          Text(
            'No minutes remain. To give a player more minutes, reduce '
            "another player's allocation first.",
            key: const ValueKey('budget-full'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  Widget _customRow(
    ThemeData theme,
    Team team,
    CourtLineup lineup,
    Player player,
    Map<String, int> targets,
  ) {
    final playerId = player.id.value;
    final seconds = targets[playerId] ?? 0;
    final starter = lineup.containsPlayer(player.id);
    final allowed = _maximumAllowed(playerId);
    final sliderMax = math.max(allowed, seconds);
    final sliderValue = seconds.clamp(0, sliderMax);

    Widget fine(String key, String label, int delta, bool enabled) => SizedBox(
      width: 44,
      height: 32,
      child: TextButton(
        key: ValueKey(key),
        onPressed: enabled ? () => _fineAdjust(playerId, delta) : null,
        style: TextButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: const Size(44, 32),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(label, style: theme.textTheme.labelSmall),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  player.fullName,
                  key: ValueKey('target-name-$playerId'),
                  style: theme.textTheme.bodyMedium,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${player.position.shortName} · '
                '${starter ? 'STARTER' : 'RESERVE'}',
                key: ValueKey('target-role-$playerId'),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                formatMinutes(seconds),
                key: ValueKey('target-seconds-$playerId'),
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: Slider(
                  key: ValueKey('target-slider-$playerId'),
                  value: sliderValue.toDouble(),
                  min: 0,
                  max: sliderMax.toDouble(),
                  divisions: sliderMax > 0 ? sliderMax : null,
                  label: formatMinutes(seconds),
                  onChanged: sliderMax > 0
                      ? (value) => _setCustomTarget(playerId, value.round())
                      : null,
                  onChangeEnd: (_) => _revalidate(),
                ),
              ),
              fine('fine-minus-$playerId', '-10s', -_fineSeconds, seconds > 0),
              fine(
                'fine-plus-$playerId',
                '+10s',
                _fineSeconds,
                seconds + _fineSeconds <= allowed,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TeamDropdown extends StatelessWidget {
  const _TeamDropdown({
    required this.label,
    required this.fieldKey,
    required this.optionKeyPrefix,
    required this.teams,
    required this.excludedTeamId,
    required this.selected,
    required this.onChanged,
  });

  final String label;
  final Key fieldKey;
  final String optionKeyPrefix;
  final List<Team> teams;

  /// The team already chosen for the other role; offering it would allow the
  /// same team on both sides.
  final TeamId? excludedTeamId;
  final Team? selected;
  final ValueChanged<Team> onChanged;

  @override
  Widget build(BuildContext context) {
    final available = [
      for (final team in teams)
        if (team.id.value != excludedTeamId?.value) team,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        DropdownButton<Team>(
          key: fieldKey,
          isExpanded: true,
          value: selected,
          hint: Text('Select $label'.toLowerCase()),
          items: [
            for (final team in available)
              DropdownMenuItem<Team>(
                key: ValueKey('$optionKeyPrefix-${team.id.value}'),
                value: team,
                child: Text(
                  '${team.abbreviation} · ${team.name}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (team) {
            if (team != null) onChanged(team);
          },
        ),
      ],
    );
  }
}

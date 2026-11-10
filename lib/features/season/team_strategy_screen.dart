import 'package:flutter/material.dart';
import 'package:simulation_core/simulation_core.dart';

import '../roster/player_profile_screen.dart';
import 'season_controller.dart';

class TeamStrategyScreen extends StatefulWidget {
  const TeamStrategyScreen({
    super.key,
    required this.league,
    required this.controller,
  });

  final League league;
  final SeasonController controller;

  @override
  State<TeamStrategyScreen> createState() => _TeamStrategyScreenState();
}

class _TeamStrategyScreenState extends State<TeamStrategyScreen> {
  late Team _userTeam;
  late List<PlayerId> _starterIds;
  late RotationPreset _preset;
  late Map<PlayerId, int> _targets;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _initFromState();
  }

  void _initFromState() {
    final state = widget.controller.state!;
    _userTeam = state.userTeam;
    _starterIds = List<PlayerId>.from(
      state.userStrategy.startingLineup.playerIds.map(PlayerId.new),
    );
    _preset = state.userStrategy.teamPlan.preset;
    _targets = Map<PlayerId, int>.from(
      state.userStrategy.teamPlan.targetSeconds,
    );
    _dirty = false;
  }

  int get _totalSeconds => _targets.values.fold(0, (sum, sec) => sum + sec);
  int get _totalMinutes => _totalSeconds ~/ 60;

  void _onPresetChanged(RotationPreset? preset) {
    if (preset == null) return;
    setState(() {
      _preset = preset;
      _dirty = true;
      if (preset != RotationPreset.custom) {
        final lineup = CourtLineup.create(
          team: _userTeam,
          slotOrderedPlayers: [
            for (final id in _starterIds)
              _userTeam.players.firstWhere((p) => p.id == id),
          ],
        );
        final expanded = RotationPlan.expandPreset(
          preset: preset,
          team: _userTeam,
          lineup: lineup,
          rules: GameRules.standard,
        );
        _targets = {for (final p in _userTeam.players) p.id: expanded[p.id]!};
      }
    });
  }

  Future<void> _save() async {
    final lineup = CourtLineup.create(
      team: _userTeam,
      slotOrderedPlayers: [
        for (final id in _starterIds)
          _userTeam.players.firstWhere((p) => p.id == id),
      ],
    );

    final targetsList = [
      for (final p in _userTeam.players)
        RotationTarget(playerId: p.id, seconds: _targets[p.id] ?? 0),
    ];

    try {
      final teamPlan = TeamRotationPlan.create(
        team: _userTeam,
        preset: _preset,
        targets: targetsList,
      );

      // Enforce strict engine validation before saving
      GameInput.validateLineupAndPlan(
        team: _userTeam,
        lineup: lineup,
        plan: teamPlan,
        rules: GameRules.standard,
      );

      final newStrategy = FranchiseStrategy(
        teamId: _userTeam.id,
        startingLineup: lineup,
        rotationPlan: RotationPlan(home: teamPlan, away: teamPlan),
      );
      await widget.controller.updateStrategy(newStrategy);
      if (!mounted) return;
      setState(() {
        _dirty = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Team strategy saved successfully!'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Cannot save strategy: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const slots = ['PG', 'SG', 'SF', 'PF', 'C'];

    return Scaffold(
      appBar: AppBar(
        title: Text('${_userTeam.name} Strategy'),
        actions: [
          TextButton(
            key: const ValueKey('save-strategy-button'),
            onPressed: _dirty ? _save : null,
            child: const Text('Save'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        children: [
          // Starting 5 Section
          Text(
            'Starting Five',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Tap a slot to assign a starter.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < 5; i++) ...[
            _buildStarterTile(context, theme, slots[i], i),
            const SizedBox(height: 6),
          ],
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),

          // Rotation Preset Section
          Text(
            'Rotation Preset',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          SegmentedButton<RotationPreset>(
            segments: const [
              ButtonSegment(
                value: RotationPreset.balanced,
                label: Text('Balanced'),
              ),
              ButtonSegment(
                value: RotationPreset.starterHeavy,
                label: Text('Starters'),
              ),
              ButtonSegment(
                value: RotationPreset.custom,
                label: Text('Custom'),
              ),
            ],
            selected: {_preset},
            onSelectionChanged: (set) => _onPresetChanged(set.first),
          ),
          const SizedBox(height: 16),

          // Playing time conservation bar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Playing Time Allocation',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '$_totalMinutes / 240 min',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: _totalMinutes == 240
                      ? Colors.green.shade700
                      : Colors.red.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Roster & Target Minutes list
          for (final player in _userTeam.players) ...[
            _buildPlayerTargetTile(context, theme, player),
            const Divider(height: 1),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildStarterTile(
    BuildContext context,
    ThemeData theme,
    String slotName,
    int slotIndex,
  ) {
    final starterId = _starterIds[slotIndex];
    final player = _userTeam.players.firstWhere((p) => p.id == starterId);

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      child: ListTile(
        key: ValueKey('starter-slot-$slotIndex'),
        leading: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary,
            shape: BoxShape.circle,
          ),
          child: Text(
            slotName,
            style: TextStyle(
              color: theme.colorScheme.onPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
        title: Text(
          player.fullName,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          'Nominal: ${player.position.shortName} - 3PT ${player.attributes.threePoint} - IQ ${player.attributes.basketballIQ}',
          style: theme.textTheme.bodySmall,
        ),
        trailing: const Icon(Icons.swap_horiz),
        onTap: () => _chooseStarter(slotIndex),
      ),
    );
  }

  void _chooseStarter(int slotIndex) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  'Select Starter',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ),
              for (final player in _userTeam.players)
                ListTile(
                  title: Text(player.fullName),
                  subtitle: Text(player.position.shortName),
                  trailing: _starterIds.contains(player.id)
                      ? const Icon(Icons.check, color: Colors.green)
                      : null,
                  onTap: () {
                    setState(() {
                      final oldStarterId = _starterIds[slotIndex];
                      final existingIndex = _starterIds.indexOf(player.id);
                      if (existingIndex != -1) {
                        // Swap starters
                        _starterIds[existingIndex] = oldStarterId;
                      }
                      _starterIds[slotIndex] = player.id;

                      // Regenerate targets immediately if using a preset
                      if (_preset != RotationPreset.custom) {
                        final newLineup = CourtLineup.create(
                          team: _userTeam,
                          slotOrderedPlayers: [
                            for (final id in _starterIds)
                              _userTeam.players.firstWhere((p) => p.id == id),
                          ],
                        );
                        final expanded = RotationPlan.expandPreset(
                          preset: _preset,
                          team: _userTeam,
                          lineup: newLineup,
                          rules: GameRules.standard,
                        );
                        _targets = {
                          for (final p in _userTeam.players)
                            p.id: expanded[p.id]!,
                        };
                      }
                      _dirty = true;
                    });
                    Navigator.pop(context);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPlayerTargetTile(
    BuildContext context,
    ThemeData theme,
    Player player,
  ) {
    final seconds = _targets[player.id] ?? 0;
    final minutes = seconds ~/ 60;
    final isStarter = _starterIds.contains(player.id);
    final stats = widget.controller.state?.playerStats[player.id.value];
    final subtitleText = stats != null && stats.gamesPlayed > 0
        ? '${player.position.shortName} • ${stats.pointsPerGame.toStringAsFixed(1)} PPG • ${stats.reboundsPerGame.toStringAsFixed(1)} RPG'
        : '${player.position.shortName} • 3PT ${player.attributes.threePoint}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: InkWell(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      PlayerProfileScreen(team: _userTeam, player: player),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        player.fullName,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      if (isStarter) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'STARTER',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  Text(subtitleText, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ),
          if (_preset == RotationPreset.custom)
            Expanded(
              flex: 5,
              child: Slider(
                value: minutes.toDouble(),
                min: 0,
                max: 48,
                divisions: 48,
                onChanged: (val) {
                  setState(() {
                    _targets[player.id] = val.toInt() * 60;
                    _dirty = true;
                  });
                },
              ),
            ),
          SizedBox(
            width: 45,
            child: Text(
              '$minutes m',
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

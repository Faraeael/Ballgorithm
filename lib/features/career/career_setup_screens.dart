import 'package:flutter/material.dart';
import 'package:simulation_core/simulation_core.dart';

typedef CareerSeedProvider = int Function();

/// Generates a fresh non-zero 31-bit seed based on current wall-clock microseconds
/// masked to 31 bits.
int defaultCareerSeedProvider() {
  final now = DateTime.now().microsecondsSinceEpoch;
  final seed = now & 0x7FFFFFFF;
  return seed == 0 ? 20261028 : seed;
}

/// Screen 1: Select franchise from the 30 fictional teams.
class CareerSelectTeamScreen extends StatefulWidget {
  const CareerSelectTeamScreen({
    super.key,
    this.seedProvider = defaultCareerSeedProvider,
  });

  final CareerSeedProvider seedProvider;

  @override
  State<CareerSelectTeamScreen> createState() => _CareerSelectTeamScreenState();
}

class _CareerSelectTeamScreenState extends State<CareerSelectTeamScreen> {
  TeamSeed _selectedTeam = teamCatalog.first;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('GM Career: Select Team')),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16.0),
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.4,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'PREVIEW',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Step 1 of 2: Choose Franchise',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Select any of the 30 fictional franchises. Your chosen competitive tier and roster will be configured in the next step.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              key: const ValueKey('career-team-list'),
              itemCount: teamCatalog.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final team = teamCatalog[index];
                final isSelected = team.id == _selectedTeam.id;

                return ListTile(
                  key: ValueKey('career-team-option-${team.id}'),
                  selected: isSelected,
                  selectedTileColor: theme.colorScheme.primaryContainer
                      .withValues(alpha: 0.25),
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
                    team.id,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  trailing: isSelected
                      ? Icon(
                          Icons.check_circle,
                          color: theme.colorScheme.primary,
                        )
                      : const Icon(Icons.radio_button_unchecked),
                  onTap: () {
                    setState(() {
                      _selectedTeam = team;
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
                key: const ValueKey('next-situation-button'),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => CareerSelectSituationScreen(
                        selectedTeam: _selectedTeam,
                        seedProvider: widget.seedProvider,
                      ),
                    ),
                  );
                },
                child: const Text('Next: Choose Starting Situation'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Screen 2: Select starting competitive situation.
class CareerSelectSituationScreen extends StatefulWidget {
  const CareerSelectSituationScreen({
    super.key,
    required this.selectedTeam,
    this.seedProvider = defaultCareerSeedProvider,
  });

  final TeamSeed selectedTeam;
  final CareerSeedProvider seedProvider;

  @override
  State<CareerSelectSituationScreen> createState() =>
      _CareerSelectSituationScreenState();
}

class _CareerSelectSituationScreenState
    extends State<CareerSelectSituationScreen> {
  FranchiseSituation _selectedSituation = FranchiseSituation.tanking;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('GM Career: Starting Situation')),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16.0),
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.4,
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.colorScheme.onPrimary,
                  child: Text(
                    widget.selectedTeam.abbreviation,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.selectedTeam.name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Step 2 of 2: Set Starting Franchise Situation',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              key: const ValueKey('career-situation-list'),
              padding: const EdgeInsets.all(16.0),
              children: [
                for (final situation in FranchiseSituation.values)
                  _buildSituationCard(context, theme, situation),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                key: const ValueKey('generate-career-preview-button'),
                onPressed: () {
                  final freshSeed = widget.seedProvider();
                  final request = CareerSetupRequest(
                    selectedTeamId: TeamId(widget.selectedTeam.id),
                    selectedSituation: _selectedSituation,
                    seed: freshSeed,
                  );
                  final result = const CareerSetupService().generate(request);

                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => CareerLeaguePreviewScreen(result: result),
                    ),
                  );
                },
                child: const Text('Generate League & Preview Roster'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSituationCard(
    BuildContext context,
    ThemeData theme,
    FranchiseSituation situation,
  ) {
    final isSelected = situation == _selectedSituation;

    return Card(
      key: ValueKey('situation-card-${situation.jsonValue}'),
      elevation: isSelected ? 2 : 0,
      margin: const EdgeInsets.only(bottom: 12.0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant,
          width: isSelected ? 2 : 1,
        ),
      ),
      color: isSelected
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.25)
          : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          setState(() {
            _selectedSituation = situation;
          });
        },
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      situation.displayName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isSelected ? theme.colorScheme.primary : null,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Opening Pick #${situation.userOpeningDraftPick}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isSelected
                            ? theme.colorScheme.onPrimary
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                situation.description,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Screen 3: Generated 30-team league and player roster preview.
class CareerLeaguePreviewScreen extends StatelessWidget {
  const CareerLeaguePreviewScreen({super.key, required this.result});

  final CareerSetupResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final team = result.selectedTeam;
    final situation = result.selectedSituation;
    final profiles = result.careerProfiles;

    return Scaffold(
      appBar: AppBar(title: const Text('GM Career Setup: Preview')),
      body: ListView(
        key: const ValueKey('career-preview-scroll'),
        padding: const EdgeInsets.all(16.0),
        children: [
          // Non-destructive preview notice
          Container(
            padding: const EdgeInsets.all(12.0),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.amber.shade300),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.amber.shade900),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Preview Mode: League generated in memory. Offseason draft and schedule systems are in development for future tasks.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.amber.shade900,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Selected Franchise Card
          Card(
            elevation: 1,
            color: theme.colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: theme.colorScheme.primary,
                        foregroundColor: theme.colorScheme.onPrimary,
                        child: Text(
                          team.abbreviation,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              team.name,
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.onPrimaryContainer,
                              ),
                            ),
                            Text(
                              situation.displayName,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          'Opening Draft Entitlement:',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: theme.colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'Pick #${result.userOpeningDraftPick}',
                          style: TextStyle(
                            color: theme.colorScheme.onPrimary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Career Seed:',
                        style: TextStyle(
                          color: theme.colorScheme.onPrimaryContainer,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        '#${result.seed}',
                        key: const ValueKey('career-seed-display'),
                        style: TextStyle(
                          color: theme.colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Roster Header
          Text(
            'Initial Generated Roster (12 Players)',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),

          // Player Roster Table
          Card(
            clipBehavior: Clip.antiAlias,
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: team.players.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final player = team.players[index];
                final profile = profiles.forPlayer(player.id);
                final overall = player.attributes.overallRating;
                final isStarter = index < 5;

                return ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 14,
                    backgroundColor: isStarter
                        ? theme.colorScheme.primary
                        : theme.colorScheme.surfaceContainerHighest,
                    foregroundColor: isStarter
                        ? theme.colorScheme.onPrimary
                        : theme.colorScheme.onSurface,
                    child: Text(
                      player.position.shortName,
                      style: const TextStyle(fontSize: 10),
                    ),
                  ),
                  title: Text(
                    player.fullName,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    'Age: ${profile?.age ?? "-"} • ${profile?.trajectory.displayName ?? "-"}',
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'OVR $overall',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'POT ${profile?.potential ?? "-"}',
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),

          // League Macro Breakdown
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '30-Team Competitive Tier Distribution',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildTierCountRow(
                    'Championship Contenders',
                    result.league.teams
                        .where(
                          (t) => t.situation == FranchiseSituation.contender,
                        )
                        .length,
                    5,
                  ),
                  _buildTierCountRow(
                    'Playoff Teams',
                    result.league.teams
                        .where((t) => t.situation == FranchiseSituation.playoff)
                        .length,
                    9,
                  ),
                  _buildTierCountRow(
                    'Play-In Contenders',
                    result.league.teams
                        .where((t) => t.situation == FranchiseSituation.playIn)
                        .length,
                    9,
                  ),
                  _buildTierCountRow(
                    'Tanking Teams',
                    result.league.teams
                        .where((t) => t.situation == FranchiseSituation.tanking)
                        .length,
                    7,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTierCountRow(String label, int count, int expected) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(label, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 8),
          Text(
            '$count / $expected teams',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

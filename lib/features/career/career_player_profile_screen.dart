import 'package:flutter/material.dart';
import 'package:simulation_core/simulation_core.dart';

import '../../theme/hardwood_command_theme.dart';
import 'career_ui_labels.dart';
import 'widgets/hardwood_components.dart';

/// Public-safe player dossier union for [CareerPlayerProfileScreen].
///
/// Enforces scouting visibility rules at the type boundary: unsigned free
/// agents and draft prospects only carry their public scouting views and
/// never expose hidden `potential` or `DevelopmentTrajectory`.
sealed class CareerPlayerDossier {
  const CareerPlayerDossier();

  String get playerId;
  String get fullName;
  Position get position;
  int get age;
  PlayerAttributes get attributes;
  int get currentYear;
}

final class RosteredPlayerDossier extends CareerPlayerDossier {
  const RosteredPlayerDossier({
    required this.player,
    required this.team,
    required this.category,
    required this.currentYear,
    required this.isUserTeam,
    this.profile,
    this.contract,
    this.schedule,
    this.seasonTotals,
  });

  final Player player;
  final Team team;
  final RosterCategory category;
  @override
  final int currentYear;
  final bool isUserTeam;
  final PlayerCareerProfile? profile;
  final PlayerContract? contract;
  final ContractFinancials? schedule;
  final SeasonPlayerTotals? seasonTotals;

  @override
  String get playerId => player.id.value;

  @override
  String get fullName => player.fullName;

  @override
  Position get position => player.position;

  @override
  int get age => profile?.age ?? 24;

  @override
  PlayerAttributes get attributes => player.attributes;
}

final class FreeAgentPlayerDossier extends CareerPlayerDossier {
  const FreeAgentPlayerDossier({
    required this.freeAgent,
    required this.currentYear,
    this.valuation,
    this.canOffer = false,
    this.onMakeOffer,
  });

  final PublicFreeAgentView freeAgent;
  @override
  final int currentYear;
  final MarketValuation? valuation;
  final bool canOffer;
  final VoidCallback? onMakeOffer;

  @override
  String get playerId => freeAgent.id.value;

  @override
  String get fullName => freeAgent.fullName;

  @override
  Position get position => freeAgent.position;

  @override
  int get age => freeAgent.age;

  @override
  PlayerAttributes get attributes => freeAgent.attributes;
}

final class DraftProspectPlayerDossier extends CareerPlayerDossier {
  const DraftProspectPlayerDossier({
    required this.prospect,
    required this.currentYear,
    this.canSelect = false,
    this.onSelectProspect,
    this.selectButtonLabel = 'Draft Prospect',
  });

  final PublicProspectScoutingView prospect;
  @override
  final int currentYear;
  final bool canSelect;
  final VoidCallback? onSelectProspect;
  final String selectButtonLabel;

  @override
  String get playerId => prospect.id.value;

  @override
  String get fullName => prospect.fullName;

  @override
  Position get position => prospect.position;

  @override
  int get age => prospect.age;

  @override
  PlayerAttributes get attributes => prospect.attributes;
}

/// Computes regular-season [SeasonPlayerTotals] for [playerId] on [teamId] from
/// completed games in [seasonState] without mutating any career state.
SeasonPlayerTotals? computeRegularSeasonPlayerTotals({
  required RegularSeasonState? seasonState,
  required String playerId,
  required String teamId,
}) {
  if (seasonState == null || seasonState.gameResults.isEmpty) {
    return null;
  }
  var totals = SeasonPlayerTotals.initial(playerId: playerId, teamId: teamId);
  for (final result in seasonState.gameResults.values) {
    final line = result.summary.playerLines[playerId];
    if (line != null) {
      totals = totals.applyGame(line);
    }
  }
  return totals.gamesPlayed > 0 ? totals : null;
}

/// Three-tab Hardwood Command player profile (`OVERVIEW`, `ATTRIBUTES`, `CONTRACT`).
class CareerPlayerProfileScreen extends StatefulWidget {
  const CareerPlayerProfileScreen({
    super.key,
    required this.dossier,
    this.initialTabIndex = 0,
  });

  final CareerPlayerDossier dossier;
  final int initialTabIndex;

  @override
  State<CareerPlayerProfileScreen> createState() =>
      _CareerPlayerProfileScreenState();
}

class _CareerPlayerProfileScreenState extends State<CareerPlayerProfileScreen> {
  late int _tabIndex = widget.initialTabIndex.clamp(0, 2);

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final dossier = widget.dossier;

    return Scaffold(
      key: ValueKey('career-player-profile-${dossier.playerId}'),
      backgroundColor: t.bgCanvas,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context, t, dossier),
            _buildTabBar(t),
            Expanded(
              child: switch (_tabIndex) {
                0 => _OverviewTab(dossier: dossier),
                1 => _AttributesTab(attributes: dossier.attributes),
                _ => _ContractTab(dossier: dossier),
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    HardwoodCommandTokens t,
    CareerPlayerDossier dossier,
  ) {
    final ovr = dossier.attributes.overallRating;
    final subtitleParts = <String>[
      dossier.position.shortName,
      'Age ${dossier.age}',
      switch (dossier) {
        RosteredPlayerDossier(:final team, :final category) =>
          '${team.abbreviation} • ${category.displayName}',
        FreeAgentPlayerDossier() => 'Free Agent',
        DraftProspectPlayerDossier(:final prospect) =>
          'Proj. #${prospect.projectedRank}',
      },
    ];

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
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          AppPressable(
            key: const ValueKey('player-profile-back'),
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
          SizedBox(width: t.space200),
          PlayerMonogramBadge(fullName: dossier.fullName, size: 38),
          SizedBox(width: t.space200),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dossier.fullName,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitleParts.join(' • '),
                  style: TextStyle(
                    color: t.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: t.space200),
          OverallRatingBadge(overall: ovr),
        ],
      ),
    );
  }

  Widget _buildTabBar(HardwoodCommandTokens t) {
    const tabs = [
      (label: 'OVERVIEW', key: ValueKey('player-tab-overview')),
      (label: 'ATTRIBUTES', key: ValueKey('player-tab-attributes')),
      (label: 'CONTRACT', key: ValueKey('player-tab-contract')),
    ];

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: t.space300,
        vertical: t.space200,
      ),
      decoration: BoxDecoration(
        color: t.bgSurface,
        border: Border(bottom: BorderSide(color: t.borderSubtle)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < tabs.length; i++) ...[
            if (i > 0) SizedBox(width: t.space200),
            Expanded(
              child: AppPressable(
                key: tabs[i].key,
                minHeight: t.touchMin,
                semanticLabel: '${tabs[i].label} tab',
                onPressed: () => setState(() => _tabIndex = i),
                child: Container(
                  constraints: BoxConstraints(minHeight: t.touchMin),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    color: _tabIndex == i ? t.accentSecondaryBg : t.bgElevated,
                    borderRadius: BorderRadius.circular(t.radiusMd),
                    border: Border.all(
                      color: _tabIndex == i
                          ? t.accentSecondary
                          : t.borderSubtle,
                    ),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      tabs[i].label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _tabIndex == i
                            ? t.accentSecondaryFg
                            : t.textSecondary,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.dossier});

  final CareerPlayerDossier dossier;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final attrs = dossier.attributes;
    final offenseAvg =
        ((attrs.insideScoring +
                    attrs.midrange +
                    attrs.threePoint +
                    attrs.freeThrow +
                    attrs.passing +
                    attrs.ballHandling) /
                6.0)
            .round();
    final defenseAvg =
        ((attrs.perimeterDefense + attrs.interiorDefense + attrs.rebounding) /
                3.0)
            .round();
    final physicalAvg =
        ((attrs.athleticism + attrs.stamina + attrs.basketballIQ) / 3.0)
            .round();

    return ListView(
      key: const ValueKey('player-overview-content'),
      padding: EdgeInsets.all(t.space300),
      children: [
        // Identity & Career Status Card
        _sectionCard(
          t,
          title: 'PLAYER IDENTITY & STATUS',
          child: Wrap(
            spacing: t.space400,
            runSpacing: t.space300,
            children: [
              _statTile(t, 'Position', dossier.position.fullName),
              _statTile(t, 'Age', '${dossier.age}'),
              _statTile(t, 'Overall', '${attrs.overallRating}'),
              ...switch (dossier) {
                RosteredPlayerDossier(
                  :final team,
                  :final category,
                  :final profile,
                ) =>
                  [
                    _statTile(t, 'Franchise', team.name),
                    _statTile(t, 'Roster Status', category.displayName),
                    if (profile != null) ...[
                      _statTile(t, 'Potential', '${profile.potential}'),
                      _statTile(
                        t,
                        'Trajectory',
                        profile.trajectory.displayName,
                      ),
                    ],
                  ],
                FreeAgentPlayerDossier(:final valuation) => [
                  _statTile(t, 'Status', 'Free Agent'),
                  if (valuation != null) ...[
                    _statTile(
                      t,
                      'Est. Market Value',
                      CareerUiLabels.formatCu(valuation.estimatedAnnualSalary),
                    ),
                    _statTile(
                      t,
                      'Expected Role',
                      valuation.expectedRole.displayName,
                    ),
                  ],
                ],
                DraftProspectPlayerDossier(:final prospect) => [
                  _statTile(t, 'Status', 'Draft Prospect'),
                  _statTile(t, 'Projected Rank', '#${prospect.projectedRank}'),
                  _statTile(
                    t,
                    'Scouted Potential',
                    '${prospect.estimatedPotentialGrade} (${prospect.estimatedPotentialRange})',
                  ),
                ],
              },
            ],
          ),
        ),
        SizedBox(height: t.space300),

        // Summary Rating Pillars
        _sectionCard(
          t,
          title: 'RATING PILLARS',
          child: LayoutBuilder(
            builder: (context, constraints) {
              final scaled = MediaQuery.textScalerOf(context).scale(14) > 20;
              if (constraints.maxWidth < 310 || scaled) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _pillarBox(t, 'OFFENSE', offenseAvg),
                    SizedBox(height: t.space200),
                    _pillarBox(t, 'DEFENSE', defenseAvg),
                    SizedBox(height: t.space200),
                    _pillarBox(t, 'PHYS / IQ', physicalAvg),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: _pillarBox(t, 'OFFENSE', offenseAvg)),
                  SizedBox(width: t.space200),
                  Expanded(child: _pillarBox(t, 'DEFENSE', defenseAvg)),
                  SizedBox(width: t.space200),
                  Expanded(child: _pillarBox(t, 'PHYS / IQ', physicalAvg)),
                ],
              );
            },
          ),
        ),
        SizedBox(height: t.space300),

        // Season Statistics Card
        _buildSeasonStatsCard(t),

        if (dossier case FreeAgentPlayerDossier(
          :final canOffer,
          :final onMakeOffer,
        ) when canOffer && onMakeOffer != null) ...[
          SizedBox(height: t.space300),
          HardwoodPrimaryCta(
            key: const ValueKey('player-profile-make-offer'),
            label: 'Make Contract Offer',
            icon: Icons.edit_document,
            onPressed: () {
              Navigator.of(context).pop();
              onMakeOffer();
            },
          ),
        ],

        if (dossier case DraftProspectPlayerDossier(
          :final canSelect,
          :final onSelectProspect,
          :final selectButtonLabel,
        ) when canSelect && onSelectProspect != null) ...[
          SizedBox(height: t.space300),
          HardwoodPrimaryCta(
            key: const ValueKey('player-profile-draft-prospect'),
            label: selectButtonLabel,
            icon: Icons.how_to_reg_rounded,
            onPressed: () {
              Navigator.of(context).pop();
              onSelectProspect();
            },
          ),
        ],
      ],
    );
  }

  Widget _buildSeasonStatsCard(HardwoodCommandTokens t) {
    final SeasonPlayerTotals? totals = switch (dossier) {
      RosteredPlayerDossier(:final seasonTotals) => seasonTotals,
      _ => null,
    };

    if (totals == null || totals.gamesPlayed == 0) {
      return _sectionCard(
        t,
        title: 'SEASON ${dossier.currentYear} STATISTICS',
        child: Text(
          'No regular-season games played in Season ${dossier.currentYear}.',
          style: TextStyle(color: t.textSecondary, fontSize: 13.5),
        ),
      );
    }

    return _sectionCard(
      t,
      title: 'SEASON ${dossier.currentYear} PER-GAME AVERAGES',
      child: Wrap(
        spacing: t.space400,
        runSpacing: t.space300,
        children: [
          _statTile(t, 'GP', '${totals.gamesPlayed}'),
          _statTile(t, 'MPG', totals.minutesPerGame.toStringAsFixed(1)),
          _statTile(t, 'PPG', totals.pointsPerGame.toStringAsFixed(1)),
          _statTile(t, 'RPG', totals.reboundsPerGame.toStringAsFixed(1)),
          _statTile(t, 'APG', totals.assistsPerGame.toStringAsFixed(1)),
          _statTile(t, 'SPG', totals.stealsPerGame.toStringAsFixed(1)),
          _statTile(t, 'BPG', totals.blocksPerGame.toStringAsFixed(1)),
          _statTile(
            t,
            'FG%',
            totals.fieldGoalPercentage == null
                ? '—'
                : '${(totals.fieldGoalPercentage! * 100).toStringAsFixed(1)}%',
          ),
          _statTile(
            t,
            '3P%',
            totals.threePointPercentage == null
                ? '—'
                : '${(totals.threePointPercentage! * 100).toStringAsFixed(1)}%',
          ),
          _statTile(
            t,
            'FT%',
            totals.freeThrowPercentage == null
                ? '—'
                : '${(totals.freeThrowPercentage! * 100).toStringAsFixed(1)}%',
          ),
        ],
      ),
    );
  }

  Widget _pillarBox(HardwoodCommandTokens t, String label, int value) {
    return Container(
      padding: EdgeInsets.all(t.space200),
      decoration: BoxDecoration(
        color: t.bgElevated,
        borderRadius: BorderRadius.circular(t.radiusMd),
        border: Border.all(color: t.borderSubtle),
      ),
      child: Column(
        children: [
          Text(
            '$value',
            style: TextStyle(
              color: t.accentSecondary,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: t.textSecondary,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _AttributesTab extends StatelessWidget {
  const _AttributesTab({required this.attributes});

  final PlayerAttributes attributes;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return ListView(
      key: const ValueKey('player-attributes-content'),
      padding: EdgeInsets.all(t.space300),
      children: [
        _sectionCard(
          t,
          title: 'OFFENSE',
          child: Column(
            children: [
              _attributeBar(t, 'Inside Scoring', attributes.insideScoring),
              _attributeBar(t, 'Midrange', attributes.midrange),
              _attributeBar(t, 'Three-Point', attributes.threePoint),
              _attributeBar(t, 'Free Throw', attributes.freeThrow),
              _attributeBar(t, 'Passing', attributes.passing),
              _attributeBar(
                t,
                'Ball Handling',
                attributes.ballHandling,
                isLast: true,
              ),
            ],
          ),
        ),
        SizedBox(height: t.space300),
        _sectionCard(
          t,
          title: 'DEFENSE',
          child: Column(
            children: [
              _attributeBar(
                t,
                'Perimeter Defense',
                attributes.perimeterDefense,
              ),
              _attributeBar(t, 'Interior Defense', attributes.interiorDefense),
              _attributeBar(
                t,
                'Rebounding',
                attributes.rebounding,
                isLast: true,
              ),
            ],
          ),
        ),
        SizedBox(height: t.space300),
        _sectionCard(
          t,
          title: 'PHYSICAL & MENTAL',
          child: Column(
            children: [
              _attributeBar(t, 'Athleticism', attributes.athleticism),
              _attributeBar(t, 'Stamina', attributes.stamina),
              _attributeBar(
                t,
                'Basketball IQ',
                attributes.basketballIQ,
                isLast: true,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _attributeBar(
    HardwoodCommandTokens t,
    String label,
    int value, {
    bool isLast = false,
  }) {
    final color = value >= 80
        ? t.statusSuccessFg
        : value >= 65
        ? t.accentSecondary
        : value >= 50
        ? t.accentPrimary
        : t.statusWarningFg;

    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : t.space200),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              SizedBox(width: t.space200),
              Text(
                '$value',
                style: TextStyle(
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(t.radiusPill),
            child: LinearProgressIndicator(
              value: (value.clamp(0, 100)) / 100.0,
              minHeight: 7,
              backgroundColor: t.bgElevated,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContractTab extends StatelessWidget {
  const _ContractTab({required this.dossier});

  final CareerPlayerDossier dossier;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return switch (dossier) {
      RosteredPlayerDossier(
        :final contract,
        :final schedule,
        :final category,
        :final currentYear,
      ) =>
        _buildRosteredContract(
          t,
          contract: contract,
          schedule: schedule,
          category: category,
          currentYear: currentYear,
        ),
      FreeAgentPlayerDossier(
        :final valuation,
        :final canOffer,
        :final onMakeOffer,
      ) =>
        ListView(
          key: const ValueKey('player-contract-content'),
          padding: EdgeInsets.all(t.space300),
          children: [
            _sectionCard(
              t,
              title: 'FREE AGENCY CONTRACT STATUS',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Unsigned Free Agent — no active franchise contract.',
                    style: TextStyle(
                      color: t.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (valuation != null) ...[
                    SizedBox(height: t.space300),
                    Wrap(
                      spacing: t.space400,
                      runSpacing: t.space200,
                      children: [
                        _statTile(
                          t,
                          'Est. Annual Salary',
                          CareerUiLabels.formatCu(
                            valuation.estimatedAnnualSalary,
                          ),
                        ),
                        _statTile(
                          t,
                          'Acceptable Range',
                          '${CareerUiLabels.formatCu(valuation.acceptableMinimum)} – '
                              '${CareerUiLabels.formatCu(valuation.acceptableMaximum)}',
                        ),
                        _statTile(
                          t,
                          'Preferred Term',
                          '${valuation.preferredDurationYears} yr(s)',
                        ),
                        _statTile(
                          t,
                          'Expected Role',
                          valuation.expectedRole.displayName,
                        ),
                      ],
                    ),
                  ],
                  if (canOffer && onMakeOffer != null) ...[
                    SizedBox(height: t.space300),
                    HardwoodPrimaryCta(
                      label: 'Make Contract Offer',
                      icon: Icons.edit_document,
                      onPressed: () {
                        Navigator.of(context).pop();
                        onMakeOffer();
                      },
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      DraftProspectPlayerDossier(:final prospect) => ListView(
        key: const ValueKey('player-contract-content'),
        padding: EdgeInsets.all(t.space300),
        children: [
          _sectionCard(
            t,
            title: 'ROOKIE SCALE ELIGIBILITY',
            child: Text(
              'Draft Prospect (Projected #${prospect.projectedRank}). '
              'Contract terms are assigned by draft-slot rookie scale upon '
              'signing after the Rookie Draft.',
              style: TextStyle(color: t.textSecondary, fontSize: 14),
            ),
          ),
        ],
      ),
    };
  }

  Widget _buildRosteredContract(
    HardwoodCommandTokens t, {
    required PlayerContract? contract,
    required ContractFinancials? schedule,
    required RosterCategory category,
    required int currentYear,
  }) {
    if (contract == null) {
      return ListView(
        key: const ValueKey('player-contract-content'),
        padding: EdgeInsets.all(t.space300),
        children: [
          _sectionCard(
            t,
            title: 'CONTRACT DETAILS',
            child: Text(
              'No active contract record found for Season $currentYear.',
              style: TextStyle(color: t.textSecondary, fontSize: 14),
            ),
          ),
        ],
      );
    }

    final remainingYears =
        (contract.startYear + contract.durationYears) - currentYear;
    final currentSalary = schedule?.salaryForYear(currentYear);

    return ListView(
      key: const ValueKey('player-contract-content'),
      padding: EdgeInsets.all(t.space300),
      children: [
        _sectionCard(
          t,
          title: 'CONTRACT TERMS',
          child: Wrap(
            spacing: t.space400,
            runSpacing: t.space300,
            children: [
              _statTile(t, 'Roster Category', category.displayName),
              _statTile(
                t,
                'Source',
                CareerUiLabels.contractSource(contract.source),
              ),
              _statTile(
                t,
                'Season $currentYear Salary',
                currentSalary == null
                    ? 'N/A'
                    : CareerUiLabels.formatCu(currentSalary),
              ),
              _statTile(
                t,
                'Remaining Years',
                remainingYears > 0 ? '$remainingYears yr(s)' : 'Expiring',
              ),
              _statTile(
                t,
                'Term',
                '${contract.startYear}–${contract.startYear + contract.durationYears - 1} (${contract.durationYears} yr)',
              ),
              if (schedule != null)
                _statTile(
                  t,
                  'Guaranteed Years',
                  '${schedule.guaranteedYears} of ${contract.durationYears}',
                ),
            ],
          ),
        ),
        if (schedule != null) ...[
          SizedBox(height: t.space300),
          _sectionCard(
            t,
            title: 'ANNUAL SALARY SCHEDULE',
            child: Column(
              children: [
                for (var i = 0; i < schedule.annualSalaries.length; i++) ...[
                  _salaryScheduleRow(
                    t,
                    year: contract.startYear + i,
                    salary: schedule.annualSalaries[i],
                    isCurrentYear: contract.startYear + i == currentYear,
                    isGuaranteed: i < schedule.guaranteedYears,
                    isLast: i == schedule.annualSalaries.length - 1,
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _salaryScheduleRow(
    HardwoodCommandTokens t, {
    required int year,
    required int salary,
    required bool isCurrentYear,
    required bool isGuaranteed,
    required bool isLast,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(
        vertical: t.space200,
        horizontal: t.space200,
      ),
      margin: EdgeInsets.only(bottom: isLast ? 0 : t.space100),
      decoration: BoxDecoration(
        color: isCurrentYear ? t.accentPrimaryTint : t.bgElevated,
        borderRadius: BorderRadius.circular(t.radiusSm),
        border: Border.all(
          color: isCurrentYear ? t.borderActive : t.borderSubtle,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Season $year${isCurrentYear ? ' (Current)' : ''}',
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 13.5,
                    fontWeight: isCurrentYear
                        ? FontWeight.w800
                        : FontWeight.w600,
                  ),
                ),
              ),
              SizedBox(width: t.space200),
              Text(
                CareerUiLabels.formatCu(salary),
                style: TextStyle(
                  color: isCurrentYear ? t.accentPrimary : t.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            isGuaranteed ? 'Guaranteed' : 'Non-Guaranteed',
            style: TextStyle(
              color: isGuaranteed ? t.statusSuccessFg : t.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

Widget _sectionCard(
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
        SizedBox(height: t.space300),
        child,
      ],
    ),
  );
}

Widget _statTile(HardwoodCommandTokens t, String label, String value) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label.toUpperCase(),
        style: TextStyle(
          color: t.textMuted,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
      const SizedBox(height: 2),
      Text(
        value,
        style: TextStyle(
          color: t.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w800,
        ),
      ),
    ],
  );
}

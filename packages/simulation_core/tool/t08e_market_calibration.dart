// T08E deterministic market calibration. Run from packages/simulation_core:
//   dart run tool/t08e_market_calibration.dart
import 'dart:io';
import 'dart:math' as math;

import 'package:simulation_core/simulation_core.dart';

const _seeds = [20261028, 1604126146, 987654321];
const _market = FreeAgentMarketValueService();
const _evaluator = FreeAgentOfferEvaluator();

GmCareer _career(int seed, FranchiseSituation situation) =>
    GmCareer.fromSetupResult(
      CareerSetupService().generate(
        CareerSetupRequest(
          selectedTeamId: const TeamId('team-1'),
          selectedSituation: situation,
          seed: seed,
        ),
      ),
      id: 't08e-$seed-${situation.jsonValue}',
    );

String _band(int ovr) => ovr >= 80
    ? '80+'
    : ovr >= 75
    ? '75-79'
    : ovr >= 70
    ? '70-74'
    : ovr >= 65
    ? '65-69'
    : ovr >= 60
    ? '60-64'
    : '<60';

String _ageBand(int age) => age <= 23
    ? '<=23'
    : age <= 28
    ? '24-28'
    : age <= 31
    ? '29-31'
    : age <= 34
    ? '32-34'
    : '35+';

String _stats(List<int> values) {
  if (values.isEmpty) return 'n/a';
  final sorted = [...values]..sort();
  final mean = (sorted.fold<int>(0, (a, b) => a + b) / sorted.length).round();
  return '${sorted.first}/${sorted[sorted.length ~/ 2]}/$mean/${sorted.last}';
}

void _writeDistribution(
  StringBuffer out,
  String title,
  Map<String, List<int>> grouped,
) {
  out.writeln('### $title');
  out.writeln();
  out.writeln('| Group | n | Min/Median/Mean/Max CU |');
  out.writeln('|---|---|---|');
  for (final key in grouped.keys.toList()..sort()) {
    out.writeln(
      '| $key | ${grouped[key]!.length} | ${_stats(grouped[key]!)} |',
    );
  }
  out.writeln();
}

void main() {
  final out = StringBuffer();
  out.writeln('# T08E market calibration (generated)');
  out.writeln();
  out.writeln(
    'Deterministic public valuation and offer policy. Test terms are '
    'simulation inputs, not market prices. No acquisition is performed.',
  );
  out.writeln();

  final byBand = <String, List<int>>{};
  final byAge = <String, List<int>>{};
  final byPosition = <String, List<int>>{};
  final durations = <int, int>{};
  final roles = <String, int>{};
  final thresholds = <int>[];
  final rejectionCounts = <String, int>{};
  final rejectedAtValue = <String, int>{};
  var noAcceptable = 0;

  for (final seed in _seeds) {
    final career = _career(seed, FranchiseSituation.playIn);
    for (final entry in career.freeAgentPool.entries) {
      final view = entry.toPublicView();
      final valuation = _market.estimate(view);
      byBand
          .putIfAbsent(_band(view.overallRating), () => [])
          .add(valuation.estimatedAnnualSalary);
      byAge
          .putIfAbsent(_ageBand(view.age), () => [])
          .add(valuation.estimatedAnnualSalary);
      byPosition
          .putIfAbsent(view.position.shortName, () => [])
          .add(valuation.estimatedAnnualSalary);
      durations[valuation.preferredDurationYears] =
          (durations[valuation.preferredDurationYears] ?? 0) + 1;
      roles[valuation.expectedRole.jsonValue] =
          (roles[valuation.expectedRole.jsonValue] ?? 0) + 1;

      final atValue = _evaluator.evaluate(
        career: career,
        teamId: career.userFranchiseId,
        freeAgentId: entry.id,
        category: RosterCategory.standard,
        durationYears: valuation.preferredDurationYears,
        agreedFirstYearSalary: valuation.estimatedAnnualSalary,
      );
      rejectedAtValue[atValue.status.jsonValue] =
          (rejectedAtValue[atValue.status.jsonValue] ?? 0) + 1;

      int? firstAcceptable;
      for (var salary = 400; salary <= 8000; salary += 50) {
        final decision = _evaluator.evaluate(
          career: career,
          teamId: career.userFranchiseId,
          freeAgentId: entry.id,
          category: RosterCategory.standard,
          durationYears: valuation.preferredDurationYears,
          agreedFirstYearSalary: salary,
        );
        if (decision.isAcceptable) {
          firstAcceptable = salary;
          break;
        }
        rejectionCounts[decision.status.jsonValue] =
            (rejectionCounts[decision.status.jsonValue] ?? 0) + 1;
      }
      if (firstAcceptable == null) {
        noAcceptable++;
      } else {
        thresholds.add(firstAcceptable);
      }
    }
  }

  _writeDistribution(out, 'Estimated salary by OVR band', byBand);
  _writeDistribution(out, 'Estimated salary by age group', byAge);
  _writeDistribution(out, 'Estimated salary by position', byPosition);

  out.writeln('### Duration and role preferences');
  out.writeln();
  out.writeln('| Preferred duration | Count |');
  out.writeln('|---|---|');
  for (final entry
      in durations.entries.toList()..sort((a, b) => a.key.compareTo(b.key))) {
    out.writeln('| ${entry.key} years | ${entry.value} |');
  }
  out.writeln();
  out.writeln('| Expected role | Count |');
  out.writeln('|---|---|');
  for (final entry
      in roles.entries.toList()..sort((a, b) => a.key.compareTo(b.key))) {
    out.writeln('| ${entry.key} | ${entry.value} |');
  }
  out.writeln();
  final exampleCareer = _career(_seeds.first, FranchiseSituation.playIn);
  final examples = <String, FreeAgentEntry>{};
  for (final entry in exampleCareer.freeAgentPool.entries) {
    final band = _band(entry.player.attributes.overallRating);
    examples.putIfAbsent(band, () => entry);
  }
  out.writeln('### Representative offers by OVR band');
  out.writeln();
  out.writeln(
    '| OVR band | OVR | Age | Preferred | Est. CU | 50% | 85% | 100% | 115% |',
  );
  out.writeln('|---|---|---|---|---|---|---|---|---|');
  for (final band in ['<60', '60-64', '65-69', '70-74', '75-79', '80+']) {
    final entry = examples[band];
    if (entry == null) continue;
    final view = entry.toPublicView();
    final valuation = _market.estimate(view);
    String decision(int salary) => _evaluator
        .evaluate(
          career: exampleCareer,
          teamId: exampleCareer.userFranchiseId,
          freeAgentId: entry.id,
          category: RosterCategory.standard,
          durationYears: valuation.preferredDurationYears,
          agreedFirstYearSalary: salary,
        )
        .status
        .jsonValue;
    final cap = FreeAgentMarketValueService.maxYearOneForDuration(
      valuation.preferredDurationYears,
    );
    final offers = [
      (valuation.estimatedAnnualSalary * 5000) ~/ 10000,
      (valuation.estimatedAnnualSalary * 8500) ~/ 10000,
      valuation.estimatedAnnualSalary,
      math.min((valuation.estimatedAnnualSalary * 11500) ~/ 10000, cap),
    ];
    out.writeln(
      '| $band | ${view.overallRating} | ${view.age} | '
      '${valuation.preferredDurationYears}y | '
      '${valuation.estimatedAnnualSalary} | '
      '${decision(offers[0])} | ${decision(offers[1])} | '
      '${decision(offers[2])} | ${decision(offers[3])} |',
    );
  }
  out.writeln();

  final young = exampleCareer.freeAgentPool.entries.firstWhere(
    (entry) => entry.profile.age <= 23,
  );
  final veteran = exampleCareer.freeAgentPool.entries
      .where((entry) => entry.profile.age >= 32)
      .reduce(
        (a, b) =>
            a.player.attributes.overallRating >=
                b.player.attributes.overallRating
            ? a
            : b,
      );
  out.writeln('### Franchise-situation examples');
  out.writeln();
  out.writeln('| Player | Situation | Offer | Decision |');
  out.writeln('|---|---|---|---|');
  for (final situation in [
    FranchiseSituation.tanking,
    FranchiseSituation.contender,
  ]) {
    final career = _career(_seeds.first, situation);
    for (final entry in [young, veteran]) {
      final valuation = _market.estimate(entry.toPublicView());
      final decision = _evaluator.evaluate(
        career: career,
        teamId: career.userFranchiseId,
        freeAgentId: entry.id,
        category: RosterCategory.standard,
        durationYears: valuation.preferredDurationYears,
        agreedFirstYearSalary: valuation.acceptableMinimum,
      );
      out.writeln(
        '| ${entry.toPublicView().fullName} (${entry.profile.age}) | '
        '${situation.displayName} | ${valuation.acceptableMinimum} CU, '
        '${valuation.preferredDurationYears}y | '
        '${decision.status.jsonValue} |',
      );
    }
  }
  out.writeln();

  out.writeln(
    '### Offer at estimated value (user team, standard, preferred duration)',
  );
  out.writeln();
  out.writeln('| Decision | Count |');
  out.writeln('|---|---|');
  for (final entry
      in rejectedAtValue.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key))) {
    out.writeln('| ${entry.key} | ${entry.value} |');
  }
  out.writeln();
  out.writeln(
    'First acceptable salary at preferred duration: ${_stats(thresholds)} CU '
    '(min/median/mean/max). No acceptable legal offer: $noAcceptable.',
  );
  out.writeln();
  out.writeln('### Rejection reasons while scanning salaries');
  out.writeln();
  out.writeln('| Reason | Count |');
  out.writeln('|---|---|');
  for (final entry
      in rejectionCounts.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key))) {
    out.writeln('| ${entry.key} | ${entry.value} |');
  }
  out.writeln();

  // Financial feasibility by valuation floor; no acquisition is simulated.
  var feasibleTeams = 0;
  var totalTeams = 0;
  final shortageCosts = <int>[];
  final infeasible = <String>[];
  for (final seed in _seeds) {
    final career = _career(seed, FranchiseSituation.playIn);
    final floors = [
      for (final entry in career.freeAgentPool.entries)
        _market.estimate(entry.toPublicView()).acceptableMinimum,
    ]..sort();
    for (final team in career.league.teams) {
      final shortage = math.max(
        0,
        RosterRules.minRegularSeasonStandard - team.roster.standardCount,
      );
      if (shortage == 0) continue;
      totalTeams++;
      final cost = floors.take(shortage).fold<int>(0, (a, b) => a + b);
      final capRoom =
          FinancialRules.salaryCap -
          career.finances.capPayrollFor(team.id, career.currentYear);
      final projected =
          career.finances.projectedEndOfSeasonCash(
            team.id,
            career.currentYear,
          ) -
          cost;
      final feasible = cost <= capRoom && projected >= 0;
      if (feasible) {
        feasibleTeams++;
      } else {
        infeasible.add(
          'seed $seed ${team.id.value}: shortage=$shortage cost=$cost '
          'capRoom=$capRoom projected=$projected',
        );
      }
      shortageCosts.add(cost);
    }
  }
  out.writeln('### Roster-completion financial feasibility (valuation floor)');
  out.writeln();
  out.writeln(
    'Teams with a standard shortage: $totalTeams; feasible under cap and cash '
    'using the cheapest valuation floors: $feasibleTeams.',
  );
  out.writeln();
  out.writeln(
    'Shortage cost min/median/mean/max: ${_stats(shortageCosts)} CU.',
  );
  out.writeln();
  if (infeasible.isNotEmpty) {
    out.writeln('Infeasible teams:');
    for (final line in infeasible) {
      out.writeln('- $line');
    }
    out.writeln();
  }
  out.writeln(
    'This is financial feasibility, not an acquisition outcome. Role fit and '
    'player acceptance can raise the actual cost above the floor.',
  );

  final file =
      File('../../specs/008-30-team-league/t08e-market-calibration-raw.md')
        ..createSync(recursive: true)
        ..writeAsStringSync(out.toString());
  stdout.writeln(out);
  stdout.writeln('wrote ${file.path}');
}

// T08G-P1 AI allocation diagnostics. Run from packages/simulation_core:
//   dart run tool/t08g_p1_allocation_diagnostics.dart before
import 'dart:io';
import 'dart:math' as math;

import 'package:simulation_core/simulation_core.dart';

const _seeds = [20261028, 1604126146, 987654321];
const _service = FreeAgentMarketService();

GmCareer _career(int seed, FranchiseSituation situation) =>
    GmCareer.fromSetupResult(
      CareerSetupService().generate(
        CareerSetupRequest(
          selectedTeamId: const TeamId('team-1'),
          selectedSituation: situation,
          seed: seed,
        ),
      ),
      id: 't08g-p1-$seed-${situation.jsonValue}',
    );

GmCareer _draft(GmCareer career) {
  const draft = DraftExecutionService();
  var current = draft.startDraft(career);
  while (!current.draftExecutionState.isCompleted) {
    current =
        current.draftExecutionState.isHumanTurn(
          order: current.draftOrder,
          userTeamId: current.userFranchiseId,
        )
        ? draft.makeHumanSelection(
            career: current,
            prospectId: current.draftExecutionState
                .availableProspects(current.draftClass)
                .first
                .id,
          )
        : draft.executeAiSelection(current);
  }
  return current;
}

GmCareer _aiRookies(GmCareer career) {
  const service = RookieAiSigningService();
  var current = service.initialize(career);
  var guard = 0;
  while (service.pendingRights(current).isNotEmpty) {
    current = service.applyNextDecision(current);
    if (++guard > 200) throw StateError('AI signing loop');
  }
  return current;
}

GmCareer _market(GmCareer career) {
  var current = _service.startRound(career);
  current = _service.prepareResolution(current);
  while (current.freeAgentMarket.isResolvable) {
    current = _service.resolveNext(current);
  }
  current = _service.startRound(current);
  current = _service.prepareResolution(current);
  while (current.freeAgentMarket.isResolvable) {
    current = _service.resolveNext(current);
  }
  return current;
}

void main(List<String> args) {
  final label = args.isEmpty ? 'current' : args.first;
  final out = StringBuffer();
  out.writeln('# T08G-P1 allocation diagnostics — $label');
  out.writeln();
  out.writeln(
    'Each row reports two market rounds. Market-only starts at year 1; '
    'offseason rows run draft + all AI rookie signings first. No human '
    'free-agent offer is staged, isolating AI allocation. No acquisition is forced.',
  );
  out.writeln();
  out.writeln(
    '| Scenario | Seed | Situation | AI offers | Unique targets | Max offers/player | AI acquisitions | Losing AI teams | Remaining | Vacancies | Outbids | Rejections | Financial unavailable | Cap-bound teams | Cash-bound teams |',
  );
  out.writeln('|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|');
  for (final mode in ['market-only', 'offseason']) {
    for (final seed in _seeds) {
      for (final situation in FranchiseSituation.values) {
        var career = _career(seed, situation);
        if (mode == 'offseason') {
          career = _aiRookies(_draft(career));
        }
        career = _market(career);
        final offers = [
          for (final round in career.freeAgentMarket.roundHistory)
            ...round.aiOffers,
        ];
        final uniqueTargets = offers.map((o) => o.playerId.value).toSet();
        final perTarget = <String, int>{};
        for (final offer in offers) {
          perTarget[offer.playerId.value] =
              (perTarget[offer.playerId.value] ?? 0) + 1;
        }
        final maxPer = perTarget.values.isEmpty
            ? 0
            : perTarget.values.reduce(math.max);
        final acquisitions = career.freeAgentPool.acquisitions;
        final aiAcquisitions = acquisitions.entries.values
            .where((record) => record.teamId != career.userFranchiseId)
            .length;
        final teamsWithSignings = {
          for (final record in acquisitions.entries.values)
            if (record.teamId != career.userFranchiseId) record.teamId.value,
        };
        final aiTeams = career.league.teams
            .where((team) => team.id != career.userFranchiseId)
            .toList();
        final losingTeams = aiTeams
            .where((team) => !teamsWithSignings.contains(team.id.value))
            .length;
        var vacancies = 0;
        var capBound = 0;
        var cashBound = 0;
        for (final team in career.league.teams) {
          vacancies += math.max(
            0,
            FinancialRules.minimumStandardRoster - team.roster.standardCount,
          );
          final capRoom =
              FinancialRules.salaryCap -
              career.finances.capPayrollFor(team.id, career.currentYear);
          final cash = career.finances.projectedEndOfSeasonCash(
            team.id,
            career.currentYear,
          );
          if (capRoom < FinancialRules.minimumSalary) capBound++;
          if (cash < FinancialRules.minimumSalary) cashBound++;
        }
        var outbids = 0;
        var rejections = 0;
        var financial = 0;
        for (final round in career.freeAgentMarket.roundHistory) {
          for (final outcome in round.outcomes) {
            for (final result in outcome.results) {
              switch (result.outcome) {
                case FreeAgentMarketOfferOutcome.outbid:
                  outbids++;
                case FreeAgentMarketOfferOutcome.rejected:
                  rejections++;
                case FreeAgentMarketOfferOutcome.financiallyUnavailable:
                  financial++;
                default:
                  break;
              }
            }
          }
        }
        out.writeln(
          '| $mode | $seed | ${situation.displayName} | ${offers.length} | '
          '${uniqueTargets.length} | $maxPer | $aiAcquisitions | '
          '$losingTeams | ${career.freeAgentPool.length} | $vacancies | '
          '$outbids | $rejections | $financial | $capBound | $cashBound |',
        );
      }
    }
  }
  final file = File(
    '../../specs/008-30-team-league/t08g-p1-allocation-$label.md',
  )..createSync(recursive: true);
  file.writeAsStringSync(out.toString());
  stdout.writeln(out);
  stdout.writeln('wrote ${file.path}');
}

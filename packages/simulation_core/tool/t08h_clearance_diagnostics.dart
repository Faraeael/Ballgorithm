// T08H clearance diagnostics. Run from packages/simulation_core:
//   dart run tool/t08h_clearance_diagnostics.dart
import 'dart:io';

import 'package:simulation_core/simulation_core.dart';

const _seeds = [20261028, 1604126146, 987654321];
const _market = FreeAgentMarketService();
const _clearance = OffseasonClearanceService();
const _gate = OffseasonReadinessGate();
const _value = FreeAgentMarketValueService();

GmCareer _career(int seed, FranchiseSituation situation) =>
    GmCareer.fromSetupResult(
      CareerSetupService().generate(
        CareerSetupRequest(
          selectedTeamId: const TeamId('team-1'),
          selectedSituation: situation,
          seed: seed,
        ),
      ),
      id: 't08h-$seed-${situation.jsonValue}',
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

GmCareer _marketRounds(GmCareer career) {
  var current = _market.startRound(career);
  current = _market.prepareResolution(current);
  while (current.freeAgentMarket.isResolvable) {
    current = _market.resolveNext(current);
  }
  current = _market.startRound(current);
  current = _market.prepareResolution(current);
  while (current.freeAgentMarket.isResolvable) {
    current = _market.resolveNext(current);
  }
  return current;
}

GmCareer _clearancePass(GmCareer career) {
  var current = _clearance.start(career);
  final human = current.userTeam;
  final humanNeed =
      RosterRules.minRegularSeasonStandard - human.roster.standardCount;
  if (humanNeed > 0) {
    for (final entry in current.freeAgentPool.entries.take(humanNeed)) {
      final valuation = _value.estimate(entry.toPublicView());
      try {
        current = _clearance.stageHumanOffer(
          career: current,
          teamId: current.userFranchiseId,
          playerId: entry.id,
          durationYears: 1,
          firstYearSalary: valuation.acceptableMaximum,
        );
      } on DomainValidationException {
        // No cap room or attempt remaining for this clearance offer.
      }
    }
  }
  current = _clearance.prepare(current);
  while (current.offseasonClearance.isResolvable) {
    current = _clearance.resolveNext(current);
  }
  return current;
}

void main() {
  final out = StringBuffer();
  out.writeln('# T08H clearance diagnostics (generated)');
  out.writeln();
  out.writeln(
    'Full sequence: career → draft → all AI rookie signings → market Rounds '
    '1+2 → readiness → one clearance pass with human minimum/acceptable offers.',
  );
  out.writeln();
  out.writeln(
    '| Seed | Situation | Gate | Ready | Below 14 | Shortage | Human shortage | Clearance acquisitions | Gate after clearance | Remaining shortage | Human after | Exceptions |',
  );
  out.writeln('|---|---|---|---|---|---|---|---|---|---|---|---|');
  for (final seed in _seeds) {
    for (final situation in FranchiseSituation.values) {
      var career = _aiRookies(_draft(_career(seed, situation)));
      career = _marketRounds(career);
      final before = _gate.evaluate(career);
      final humanShortage = before.humanShortage;
      final acquisitionsBefore = career.freeAgentPool.acquisitions.length;
      final cleared = _clearancePass(career);
      final after = _gate.evaluate(cleared);
      final acquisitions =
          cleared.freeAgentPool.acquisitions.length - acquisitionsBefore;
      out.writeln(
        '| $seed | ${situation.displayName} | ${before.status.jsonValue} | '
        '${before.readyCount} | ${before.belowMinimumCount} | '
        '${before.totalShortage} | $humanShortage | $acquisitions | '
        '${after.status.jsonValue} | ${after.totalShortage} | '
        '${after.humanShortage} | ${cleared.offseasonClearance.capExceptions.map((e) => '${e.teamId.value}:${e.amount}').join(',')} |',
      );
      if (before.status ==
          OffseasonReadinessStatus.financialExceptionRequired) {
        for (final team in before.teams) {
          if (team.requiredPlayers > 0 &&
              team.capRoom < 400 * team.requiredPlayers) {
            out.writeln(
              '|  | blocker | ${team.abbreviation} needs '
              '${team.requiredPlayers}, cap room ${team.capRoom}, cash '
              '${team.cash}, projected ${team.projectedCash}, acceptable '
              '${team.acceptableOffers} |  |  |  |  |  |  |',
            );
          }
        }
      }
    }
  }
  final file = File(
    '../../specs/008-30-team-league/t08h-clearance-diagnostics.md',
  )..createSync(recursive: true);
  file.writeAsStringSync(out.toString());
  stdout.writeln(out);
  stdout.writeln('wrote ${file.path}');
}

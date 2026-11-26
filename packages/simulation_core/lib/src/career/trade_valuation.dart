import 'dart:math' as math;

import '../finance/financial_rules.dart';
import '../models/ids.dart';
import '../models/player.dart';
import '../models/position.dart';
import '../models/team.dart';
import 'gm_career.dart';
import 'trade_service.dart';

enum TradeEvaluationReason {
  accepted,
  missingNaturalPosition,
  eliteReplacement,
  guaranteeBurden,
  insufficientValue,
}

final class TradeValuation {
  const TradeValuation({
    required this.accepted,
    required this.reason,
    required this.strategy,
    required this.basketball,
    required this.control,
    required this.finance,
    required this.draft,
    required this.score,
    required this.threshold,
  });

  final bool accepted;
  final TradeEvaluationReason reason;
  final FranchiseTradeStrategy strategy;
  final int basketball;
  final int control;
  final int finance;
  final int draft;
  final int score;
  final int threshold;
}

enum FranchiseTradeStrategy { contending, middle, rebuilding }

/// Deterministic, public-input AI trade evaluation. No random state consumed.
abstract final class TradeValuationService {
  static TradeValuation evaluate(
    GmCareer before,
    PlayerTradeProposal proposal,
    GmCareer after,
  ) {
    final aiId = proposal.firstTeam == before.userFranchiseId
        ? proposal.secondTeam
        : proposal.firstTeam;
    final teamBefore = before.league.teams.firstWhere((t) => t.id == aiId);
    final teamAfter = after.league.teams.firstWhere((t) => t.id == aiId);
    final strategy = _strategy(before, teamBefore);
    final beforePlayers = _rotation(teamBefore);
    final afterPlayers = _rotation(teamAfter);
    final basketball = _basketball(afterPlayers) - _basketball(beforePlayers);
    final control =
        _control(afterPlayers, after, aiId) -
        _control(beforePlayers, before, aiId);
    final finance = _finance(before, after, aiId);
    final draft = _draftValue(before, proposal, aiId);
    final score = _score(strategy, basketball, control, finance, draft);
    final threshold = switch (strategy) {
      FranchiseTradeStrategy.contending => 8,
      FranchiseTradeStrategy.middle => 6,
      FranchiseTradeStrategy.rebuilding => 5,
    };
    final beforePositions = _positionCounts(teamBefore.roster.standardPlayers);
    final afterPositions = _positionCounts(teamAfter.roster.standardPlayers);
    if (Position.values.any(
      (p) => beforePositions[p]! > 0 && afterPositions[p] == 0,
    )) {
      return _result(
        false,
        TradeEvaluationReason.missingNaturalPosition,
        strategy,
        basketball,
        control,
        finance,
        draft,
        score,
        threshold,
      );
    }
    final outgoing = _departedTopTwo(beforePlayers, teamBefore, teamAfter);
    if (outgoing.isNotEmpty) {
      final incoming = _incomingStarters(teamBefore, teamAfter);
      final covered = _matchElite(outgoing, incoming);
      final pickFour = _hasIncomingTopFivePick(proposal, aiId);
      final rebuildException =
          strategy == FranchiseTradeStrategy.rebuilding &&
          outgoing.length == 1 &&
          pickFour &&
          draft >= 80 &&
          before.finances.capPayrollFor(aiId, before.currentYear) -
                  after.finances.capPayrollFor(aiId, before.currentYear) >=
              800;
      if (!covered && !rebuildException) {
        return _result(
          false,
          TradeEvaluationReason.eliteReplacement,
          strategy,
          basketball,
          control,
          finance,
          draft,
          score,
          threshold,
        );
      }
    }
    final guaranteeIncrease =
        _guaranteedCash(after, aiId) - _guaranteedCash(before, aiId);
    final nonFinancial = _score(strategy, basketball, control, 0, draft);
    if (guaranteeIncrease > 0 &&
        nonFinancial <= guaranteeIncrease ~/ FinancialRules.minimumSalary) {
      return _result(
        false,
        TradeEvaluationReason.guaranteeBurden,
        strategy,
        basketball,
        control,
        finance,
        draft,
        score,
        threshold,
      );
    }
    return _result(
      score > threshold,
      score > threshold
          ? TradeEvaluationReason.accepted
          : TradeEvaluationReason.insufficientValue,
      strategy,
      basketball,
      control,
      finance,
      draft,
      score,
      threshold,
    );
  }

  static TradeValuation _result(
    bool accepted,
    TradeEvaluationReason reason,
    FranchiseTradeStrategy strategy,
    int basketball,
    int control,
    int finance,
    int draft,
    int score,
    int threshold,
  ) => TradeValuation(
    accepted: accepted,
    reason: reason,
    strategy: strategy,
    basketball: basketball,
    control: control,
    finance: finance,
    draft: draft,
    score: score,
    threshold: threshold,
  );

  static FranchiseTradeStrategy _strategy(GmCareer career, Team team) {
    final history = career.seasonHistory.reversed.firstOrNull;
    if (history != null) {
      final standing = history.regularSeasonStandings
          .where((s) => s.teamId == team.id)
          .firstOrNull;
      if (standing != null) {
        return standing.rank <= 8
            ? FranchiseTradeStrategy.contending
            : standing.rank <= 20
            ? FranchiseTradeStrategy.middle
            : FranchiseTradeStrategy.rebuilding;
      }
    }
    final ordered = career.league.teams.toList()
      ..sort((a, b) {
        final difference =
            _rotation(b).starters.fold<int>(
              0,
              (sum, p) => sum + p.attributes.overallRating,
            ) -
            _rotation(a).starters.fold<int>(
              0,
              (sum, p) => sum + p.attributes.overallRating,
            );
        return difference != 0 ? difference : a.id.value.compareTo(b.id.value);
      });
    final rank = ordered.indexWhere((t) => t.id == team.id) + 1;
    return rank <= 8
        ? FranchiseTradeStrategy.contending
        : rank <= 20
        ? FranchiseTradeStrategy.middle
        : FranchiseTradeStrategy.rebuilding;
  }

  static _Rotation _rotation(Team team) {
    final remaining = team.roster.standardPlayers.toList();
    final starters = <Player>[];
    for (final position in Position.values) {
      final same = remaining.where((p) => p.position == position).toList()
        ..sort(_playerOrder(team));
      if (same.isNotEmpty) {
        starters.add(same.first);
        remaining.remove(same.first);
      }
    }
    remaining.sort(_playerOrder(team));
    while (starters.length < 5 && remaining.isNotEmpty) {
      starters.add(remaining.removeAt(0));
    }
    remaining.sort(_playerOrder(team));
    final twoWay = team.roster.twoWayPlayers.toList()..sort(_playerOrder(team));
    final twoWayValue = twoWay
        .take(2)
        .fold<int>(
          0,
          (sum, p) => sum + math.max(0, p.attributes.overallRating - 50) ~/ 4,
        );
    return _Rotation(
      starters,
      remaining.take(5).toList(),
      _positionCounts(
        team.roster.standardPlayers,
      ).values.where((count) => count >= 2).length,
      twoWayValue,
    );
  }

  static int Function(Player, Player) _playerOrder(Team team) {
    final order = {
      for (var i = 0; i < team.players.length; i++) team.players[i].id: i,
    };
    return (a, b) {
      final rating = b.attributes.overallRating.compareTo(
        a.attributes.overallRating,
      );
      if (rating != 0) return rating;
      final roster = order[a.id]!.compareTo(order[b.id]!);
      return roster != 0 ? roster : a.id.value.compareTo(b.id.value);
    };
  }

  static int _basketball(_Rotation rotation) {
    int value(Player p, int weight) =>
        weight * math.max(0, p.attributes.overallRating - 50).toInt();
    return rotation.starters.fold<int>(0, (sum, p) => sum + value(p, 4)) +
        rotation.reserves.fold<int>(0, (sum, p) => sum + value(p, 2)) +
        6 * rotation.coveredPositions +
        rotation.twoWayValue;
  }

  static Map<Position, int> _positionCounts(Iterable<Player> players) {
    final counts = {for (final p in Position.values) p: 0};
    for (final player in players) {
      counts[player.position] = counts[player.position]! + 1;
    }
    return counts;
  }

  static int _control(_Rotation rotation, GmCareer career, TeamId teamId) {
    var score = 0;
    for (final player in [...rotation.starters, ...rotation.reserves]) {
      final age = career.careerProfiles.forPlayer(player.id)?.age;
      final contract = career.finances.contractForPlayer(player.id);
      final schedule = contract == null
          ? null
          : career.finances.scheduleFor(contract.id);
      if (age == null ||
          contract == null ||
          schedule == null ||
          contract.teamId != teamId) {
        continue;
      }
      final q = math.max(0, player.attributes.overallRating - 50);
      final salaryLimit = math.min(4000, 100 * q);
      final ageFactor = math.min(6, math.max(0, 27 - age));
      final last = contract.startYear + contract.durationYears - 1;
      for (var year = career.currentYear + 1; year <= last; year++) {
        if ((schedule.salaryForYear(year) ?? 0) <= salaryLimit) {
          score += ageFactor;
        }
      }
    }
    return score;
  }

  static int _finance(GmCareer before, GmCareer after, TeamId teamId) {
    var difference = 0;
    for (
      var year = before.currentYear;
      year <= before.currentYear + 4;
      year++
    ) {
      difference +=
          before.finances.cashPayrollFor(teamId, year) -
          after.finances.cashPayrollFor(teamId, year);
    }
    final beforeCount = before.league.teams
        .firstWhere((t) => t.id == teamId)
        .roster
        .standardCount;
    final afterCount = after.league.teams
        .firstWhere((t) => t.id == teamId)
        .roster
        .standardCount;
    difference +=
        FinancialRules.minimumSalary *
        (math.max(0, 14 - beforeCount) - math.max(0, 14 - afterCount));
    return difference ~/ FinancialRules.minimumSalary;
  }

  static int _guaranteedCash(GmCareer career, TeamId teamId) {
    var total = 0;
    for (
      var year = career.currentYear;
      year <= career.currentYear + 4;
      year++
    ) {
      total += career.finances.guaranteedLiabilityCashFor(teamId, year);
      for (final schedule in career.finances.schedulesForTeam(teamId)) {
        if (year >= schedule.signedYear &&
            year < schedule.signedYear + schedule.guaranteedYears) {
          total += schedule.salaryForYear(year) ?? 0;
        }
      }
    }
    final count = career.league.teams
        .firstWhere((t) => t.id == teamId)
        .roster
        .standardCount;
    return total +
        FinancialRules.minimumSalary * math.max(0, 14 - count).toInt();
  }

  static int _score(
    FranchiseTradeStrategy strategy,
    int b,
    int c,
    int f,
    int d,
  ) => switch (strategy) {
    FranchiseTradeStrategy.contending =>
      (13 * b + 5 * c + 10 * f + 7 * d) ~/ 10,
    FranchiseTradeStrategy.middle => b + c + f + d,
    FranchiseTradeStrategy.rebuilding =>
      (8 * b + 15 * c + 10 * f + 15 * d) ~/ 10,
  };

  static int _pickValue(int slot) => switch (slot) {
    <= 5 => 96,
    <= 14 => 64,
    <= 30 => 36,
    <= 45 => 14,
    _ => 5,
  };

  static int _draftValue(
    GmCareer career,
    PlayerTradeProposal proposal,
    TeamId ai,
  ) {
    final incomingPicks = ai == proposal.firstTeam
        ? proposal.picksFromSecond
        : proposal.picksFromFirst;
    final outgoingPicks = ai == proposal.firstTeam
        ? proposal.picksFromFirst
        : proposal.picksFromSecond;
    final incomingRights = ai == proposal.firstTeam
        ? proposal.rightsFromSecond
        : proposal.rightsFromFirst;
    final outgoingRights = ai == proposal.firstTeam
        ? proposal.rightsFromFirst
        : proposal.rightsFromSecond;
    var total =
        incomingPicks.fold<int>(0, (s, a) => s + _pickValue(a.overallPick)) -
        outgoingPicks.fold<int>(0, (s, a) => s + _pickValue(a.overallPick));
    for (final a in incomingRights) {
      total += _rightValue(career, a.prospectId, a.overallPick);
    }
    for (final a in outgoingRights) {
      total -= _rightValue(career, a.prospectId, a.overallPick);
    }
    return total;
  }

  static int _rightValue(GmCareer career, PlayerId id, int slot) {
    final current = career.draftClass.byId(id);
    final carried = career.carriedUnsignedProspects[id.value];
    final age = current?.age ?? carried?.age ?? 23;
    final grade =
        current?.estimatedPotentialGrade ??
        carried?.estimatedPotentialGrade ??
        '';
    const points = {
      'A+': 18,
      'A': 15,
      'A-': 12,
      'B+': 9,
      'B': 6,
      'B-': 4,
      'C+': 2,
      'C': 0,
    };
    return _pickValue(slot) ~/ 4 +
        math.min(5, math.max(0, 23 - age)).toInt() +
        (points[grade] ?? 0);
  }

  static List<Player> _departedTopTwo(
    _Rotation before,
    Team beforeTeam,
    Team after,
  ) {
    final top = before.starters.toList()..sort(_playerOrder(beforeTeam));
    return [
      for (final p in top.take(2))
        if (!after.players.any((x) => x.id == p.id)) p,
    ];
  }

  static List<Player> _incomingStarters(Team before, Team after) => [
    for (final p in after.roster.standardPlayers)
      if (!before.players.any((old) => old.id == p.id) &&
          _rotation(after).starters.any((s) => s.id == p.id))
        p,
  ]..sort(_playerOrder(after));

  static bool _matchElite(List<Player> outgoing, List<Player> incoming) {
    final used = <PlayerId>{};
    for (final lost in outgoing) {
      final match = incoming
          .where(
            (player) =>
                !used.contains(player.id) &&
                player.attributes.overallRating >=
                    lost.attributes.overallRating - 5,
          )
          .firstOrNull;
      if (match == null) return false;
      used.add(match.id);
    }
    return true;
  }

  static bool _hasIncomingTopFivePick(PlayerTradeProposal p, TeamId ai) =>
      (ai == p.firstTeam ? p.picksFromSecond : p.picksFromFirst).any(
        (pick) => pick.overallPick <= 5,
      );
}

final class _Rotation {
  const _Rotation(
    this.starters,
    this.reserves,
    this.coveredPositions,
    this.twoWayValue,
  );
  final List<Player> starters;
  final List<Player> reserves;
  final int coveredPositions;
  final int twoWayValue;
}

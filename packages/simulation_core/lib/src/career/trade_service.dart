import 'dart:math' as math;

import '../draft/ai_rookie_signing_service.dart';
import '../finance/career_finances.dart';
import '../finance/financial_rules.dart';
import '../models/contract_financials.dart';
import '../models/draft_execution_state.dart';
import '../models/draft_order.dart';
import '../models/draft_pick.dart';
import '../models/draft_rights.dart';
import '../models/free_agent_market.dart';
import '../models/hardship_settlement.dart';
import '../models/ids.dart';
import '../models/league.dart';
import '../models/offseason_clearance.dart';
import '../models/player.dart';
import '../models/player_contract.dart';
import '../models/roster.dart';
import '../models/roster_category.dart';
import '../models/roster_rules.dart';
import '../models/team.dart';
import '../validation/validation_result.dart';
import 'career_phase.dart';
import 'gm_career.dart';
import 'trade_record.dart';

typedef PlayerTradeAsset = ({PlayerId playerId, String contractId});
typedef DraftPickTradeAsset = ({
  int draftYear,
  int overallPick,
  TeamId expectedOwner,
});
typedef DraftRightsTradeAsset = ({
  PlayerId prospectId,
  int draftYear,
  int overallPick,
  TeamId expectedOwner,
});

final class PlayerTradeProposal {
  PlayerTradeProposal({
    required this.careerId,
    required this.seasonYear,
    required this.expectedTradeCount,
    required this.firstTeam,
    required this.secondTeam,
    Iterable<PlayerTradeAsset> fromFirst = const [],
    Iterable<PlayerTradeAsset> fromSecond = const [],
    Iterable<DraftPickTradeAsset> picksFromFirst = const [],
    Iterable<DraftPickTradeAsset> picksFromSecond = const [],
    Iterable<DraftRightsTradeAsset> rightsFromFirst = const [],
    Iterable<DraftRightsTradeAsset> rightsFromSecond = const [],
  }) : fromFirst = _players(fromFirst),
       fromSecond = _players(fromSecond),
       picksFromFirst = _picks(picksFromFirst),
       picksFromSecond = _picks(picksFromSecond),
       rightsFromFirst = _rights(rightsFromFirst),
       rightsFromSecond = _rights(rightsFromSecond);

  final String careerId;
  final int seasonYear;
  final int expectedTradeCount;
  final TeamId firstTeam;
  final TeamId secondTeam;
  final List<PlayerTradeAsset> fromFirst;
  final List<PlayerTradeAsset> fromSecond;
  final List<DraftPickTradeAsset> picksFromFirst;
  final List<DraftPickTradeAsset> picksFromSecond;
  final List<DraftRightsTradeAsset> rightsFromFirst;
  final List<DraftRightsTradeAsset> rightsFromSecond;

  bool get isEmpty =>
      fromFirst.isEmpty &&
      fromSecond.isEmpty &&
      picksFromFirst.isEmpty &&
      picksFromSecond.isEmpty &&
      rightsFromFirst.isEmpty &&
      rightsFromSecond.isEmpty;

  static List<PlayerTradeAsset> _players(Iterable<PlayerTradeAsset> values) =>
      List.unmodifiable(
        values.toList()
          ..sort((a, b) => a.playerId.value.compareTo(b.playerId.value)),
      );
  static List<DraftPickTradeAsset> _picks(
    Iterable<DraftPickTradeAsset> values,
  ) => List.unmodifiable(
    values.toList()..sort((a, b) => a.overallPick.compareTo(b.overallPick)),
  );
  static List<DraftRightsTradeAsset> _rights(
    Iterable<DraftRightsTradeAsset> values,
  ) => List.unmodifiable(
    values.toList()
      ..sort((a, b) => a.prospectId.value.compareTo(b.prospectId.value)),
  );
}

enum PlayerTradeRejection {
  windowClosed,
  invalidFranchises,
  emptySide,
  duplicateAsset,
  staleProposal,
  unavailableAsset,
  staleOwnership,
  staleContract,
  alreadyTraded,
  rosterLimit,
  capPayroll,
  futureCapPayroll,
  cashReserve,
  invalidCareer,
}

final class PlayerTradeRejected implements Exception {
  const PlayerTradeRejected(
    this.reason, {
    this.teamId,
    this.playerId,
    this.detail,
  });
  final PlayerTradeRejection reason;
  final TeamId? teamId;
  final PlayerId? playerId;
  final Object? detail;
  @override
  String toString() =>
      'Player trade rejected: ${reason.name}'
      '${teamId == null ? '' : ' (${teamId!.value})'}'
      '${playerId == null ? '' : ' [${playerId!.value}]'}'
      '${detail == null ? '' : ': $detail'}';
}

typedef _Move = ({
  Player player,
  PlayerContract contract,
  ContractFinancials schedule,
  TeamId to,
});

/// Pure candidate construction; public callers must use acceptance validation.
abstract final class PlayerTradeService {
  static GmCareer buildCandidate(
    GmCareer career,
    PlayerTradeProposal proposal,
  ) {
    if (!_windowOpen(career)) {
      throw const PlayerTradeRejected(PlayerTradeRejection.windowClosed);
    }
    if (proposal.careerId != career.id ||
        proposal.seasonYear != career.currentYear ||
        proposal.expectedTradeCount != career.tradeHistory.length) {
      throw const PlayerTradeRejected(PlayerTradeRejection.staleProposal);
    }
    final first = career.league.teams
        .where((t) => t.id == proposal.firstTeam)
        .firstOrNull;
    final second = career.league.teams
        .where((t) => t.id == proposal.secondTeam)
        .firstOrNull;
    if (first == null ||
        second == null ||
        first.id == second.id ||
        (first.id != career.userFranchiseId &&
            second.id != career.userFranchiseId)) {
      throw const PlayerTradeRejected(PlayerTradeRejection.invalidFranchises);
    }
    bool hasAssets(
      List<PlayerTradeAsset> players,
      List<DraftPickTradeAsset> picks,
      List<DraftRightsTradeAsset> rights,
    ) => players.isNotEmpty || picks.isNotEmpty || rights.isNotEmpty;
    if (!hasAssets(
          proposal.fromFirst,
          proposal.picksFromFirst,
          proposal.rightsFromFirst,
        ) ||
        !hasAssets(
          proposal.fromSecond,
          proposal.picksFromSecond,
          proposal.rightsFromSecond,
        )) {
      throw const PlayerTradeRejected(PlayerTradeRejection.emptySide);
    }
    final ids = <PlayerId>{};
    final contractIds = <String>{};
    final assetKeys = <String>{};
    for (final asset in [...proposal.fromFirst, ...proposal.fromSecond]) {
      if (!ids.add(asset.playerId) ||
          !contractIds.add(asset.contractId) ||
          !assetKeys.add('player:${asset.playerId.value}')) {
        throw PlayerTradeRejected(
          PlayerTradeRejection.duplicateAsset,
          playerId: asset.playerId,
        );
      }
    }
    for (final asset in [
      ...proposal.picksFromFirst,
      ...proposal.picksFromSecond,
    ]) {
      if (!assetKeys.add('pick:${asset.draftYear}:${asset.overallPick}')) {
        throw const PlayerTradeRejected(PlayerTradeRejection.duplicateAsset);
      }
    }
    for (final asset in [
      ...proposal.rightsFromFirst,
      ...proposal.rightsFromSecond,
    ]) {
      if (!ids.add(asset.prospectId) ||
          !assetKeys.add(
            'rights:${asset.draftYear}:${asset.prospectId.value}',
          )) {
        throw PlayerTradeRejected(
          PlayerTradeRejection.duplicateAsset,
          playerId: asset.prospectId,
        );
      }
    }
    final previousKeys = {
      for (final record in career.tradeHistory)
        if (record.seasonYear == career.currentYear)
          for (final a in record.assets) a.canonicalKey,
    };
    if (assetKeys.any(previousKeys.contains)) {
      throw const PlayerTradeRejected(PlayerTradeRejection.alreadyTraded);
    }
    final pickMoves = <int, TeamId>{};
    final rightsMoves = <String, TeamId>{};
    final moves = <String, _Move>{};
    void resolve(Team from, Team to, List<PlayerTradeAsset> assets) {
      for (final asset in assets) {
        final current = career.finances.contractForPlayer(asset.playerId);
        final player = from.players
            .where((p) => p.id == asset.playerId)
            .firstOrNull;
        final schedule = current == null
            ? null
            : career.finances.scheduleFor(current.id);
        Never reject(PlayerTradeRejection reason) => throw PlayerTradeRejected(
          reason,
          teamId: from.id,
          playerId: asset.playerId,
        );
        if (current == null) reject(PlayerTradeRejection.unavailableAsset);
        if (current.teamId != from.id || player == null) {
          reject(PlayerTradeRejection.staleOwnership);
        }
        if (current.id != asset.contractId) {
          reject(PlayerTradeRejection.staleContract);
        }
        if (!current.isActiveIn(career.currentYear) ||
            schedule == null ||
            current.category == RosterCategory.trainingCamp ||
            current.category != from.roster.categoryOf(player.id)) {
          reject(PlayerTradeRejection.unavailableAsset);
        }
        moves[current.id] = (
          player: player,
          contract: current,
          schedule: schedule,
          to: to.id,
        );
      }
    }

    resolve(first, second, proposal.fromFirst);
    resolve(second, first, proposal.fromSecond);
    void resolvePicks(Team from, Team to, List<DraftPickTradeAsset> assets) {
      for (final asset in assets) {
        if (career.currentYear != asset.draftYear ||
            !career.draftExecutionState.isNotStarted ||
            asset.overallPick < 1 ||
            asset.overallPick > career.draftOrder.totalPicks) {
          throw const PlayerTradeRejected(
            PlayerTradeRejection.unavailableAsset,
          );
        }
        final pick = career.draftOrder.pickAt(asset.overallPick);
        if (pick.currentOwnerTeamId != asset.expectedOwner ||
            pick.currentOwnerTeamId != from.id) {
          throw PlayerTradeRejected(
            PlayerTradeRejection.staleOwnership,
            teamId: from.id,
          );
        }
        pickMoves[asset.overallPick] = to.id;
      }
    }

    void resolveRights(Team from, Team to, List<DraftRightsTradeAsset> assets) {
      for (final asset in assets) {
        final current = asset.draftYear == career.currentYear
            ? career.draftExecutionState.draftRights[asset.prospectId.value]
            : career.careerDraftRights[asset.prospectId.value];
        if (current == null ||
            career.rookieSigningLedger.isSigned(asset.prospectId) ||
            current.seasonYear != asset.draftYear ||
            current.overallPick != asset.overallPick) {
          throw PlayerTradeRejected(
            PlayerTradeRejection.unavailableAsset,
            teamId: from.id,
            playerId: asset.prospectId,
          );
        }
        if (current.owningTeamId != asset.expectedOwner ||
            current.owningTeamId != from.id) {
          throw PlayerTradeRejected(
            PlayerTradeRejection.staleOwnership,
            teamId: from.id,
            playerId: asset.prospectId,
          );
        }
        if (asset.draftYear == career.currentYear &&
            (!career.draftExecutionState.isCompleted ||
                const RookieAiSigningService()
                    .pendingRights(career)
                    .isNotEmpty)) {
          throw const PlayerTradeRejected(PlayerTradeRejection.windowClosed);
        }
        rightsMoves[asset.prospectId.value] = to.id;
      }
    }

    resolvePicks(first, second, proposal.picksFromFirst);
    resolvePicks(second, first, proposal.picksFromSecond);
    resolveRights(first, second, proposal.rightsFromFirst);
    resolveRights(second, first, proposal.rightsFromSecond);
    final nextDraftOrder = pickMoves.isEmpty
        ? career.draftOrder
        : DraftOrder(
            picks: [
              for (final pick in career.draftOrder.picks)
                DraftPick(
                  round: pick.round,
                  pickInRound: pick.pickInRound,
                  overallPick: pick.overallPick,
                  originalOwnerTeamId: pick.originalOwnerTeamId,
                  currentOwnerTeamId:
                      pickMoves[pick.overallPick] ?? pick.currentOwnerTeamId,
                ),
            ],
          );
    final nextDraftState = rightsMoves.isEmpty
        ? career.draftExecutionState
        : DraftExecutionState(
            status: career.draftExecutionState.status,
            selections: career.draftExecutionState.selections,
            draftRights: {
              for (final entry
                  in career.draftExecutionState.draftRights.entries)
                entry.key: DraftRights(
                  prospectId: entry.value.prospectId,
                  owningTeamId:
                      rightsMoves[entry.key] ?? entry.value.owningTeamId,
                  overallPick: entry.value.overallPick,
                  seasonYear: entry.value.seasonYear,
                ),
            },
          );
    final nextCareerRights = rightsMoves.isEmpty
        ? career.careerDraftRights
        : {
            for (final entry in career.careerDraftRights.entries)
              entry.key: DraftRights(
                prospectId: entry.value.prospectId,
                owningTeamId:
                    rightsMoves[entry.key] ?? entry.value.owningTeamId,
                overallPick: entry.value.overallPick,
                seasonYear: entry.value.seasonYear,
              ),
          };
    final nextFirst = _rosterAfter(first, ids, moves.values);
    final nextSecond = _rosterAfter(second, ids, moves.values);
    final before = career.finances;
    final after = CareerFinances(
      contracts: [
        for (final c in before.contracts.values)
          if (moves[c.id] case final move?)
            PlayerContract(
              id: c.id,
              playerId: c.playerId,
              teamId: move.to,
              category: c.category,
              startYear: c.startYear,
              durationYears: c.durationYears,
              source: c.source,
              rookieContractId: c.rookieContractId,
            )
          else
            c,
      ],
      schedules: [
        for (final s in before.schedules.values)
          if (moves[s.contractId] case final move?)
            ContractFinancials(
              contractId: s.contractId,
              playerId: s.playerId,
              teamId: move.to,
              annualSalaries: s.annualSalaries,
              guaranteedYears: s.guaranteedYears,
              source: s.source,
              signedYear: s.signedYear,
            )
          else
            s,
      ],
      teamFinances: before.teamFinances.values,
      staffCommitments: before.staffCommitments.values,
      facilities: before.facilities.values,
      guaranteedLiabilities: before.guaranteedLiabilities.values,
      debtByTeam: before.debtByTeam,
    );
    final year = career.currentYear;
    final lastYear = moves.values.fold(
      year,
      (last, move) => math.max(
        last,
        move.contract.startYear + move.contract.durationYears - 1,
      ),
    );
    _validateMoney(before, after, nextFirst, year, lastYear, moves.isEmpty);
    _validateMoney(before, after, nextSecond, year, lastYear, moves.isEmpty);
    final league = League.create(
      id: career.league.id,
      name: career.league.name,
      config: career.league.config,
      teams: [
        for (final team in career.league.teams)
          if (team.id == first.id)
            nextFirst
          else if (team.id == second.id)
            nextSecond
          else
            team,
      ],
      enforceRosterSize: false,
      enforcePositionCoverage: false,
    );
    TeamId rightsOriginalOwner(DraftRights asset) {
      for (final selection in career.draftExecutionState.selections) {
        if (selection.prospectId == asset.prospectId &&
            selection.seasonYear == asset.seasonYear) {
          return selection.selectingTeamId;
        }
      }
      for (final record in career.tradeHistory) {
        for (final transfer in record.assets) {
          if (transfer.kind == TradeAssetKind.rights &&
              transfer.playerId == asset.prospectId &&
              transfer.draftYear == asset.seasonYear) {
            return transfer.originalOwner!;
          }
        }
      }
      return asset.owningTeamId;
    }

    final receipt = TradeRecord(
      seasonYear: year,
      sequence: career.tradeHistory.length + 1,
      firstTeam: first.id,
      secondTeam: second.id,
      assets: [
        for (final move in moves.values)
          TradeAssetTransfer.player(
            playerId: move.player.id,
            contractId: move.contract.id,
            from: move.contract.teamId,
            to: move.to,
            startYear: move.contract.startYear,
            endYear: move.contract.startYear + move.contract.durationYears - 1,
            termsDigest: TradeRecord.termsDigest(move.contract, move.schedule),
          ),
        for (final asset in proposal.picksFromFirst)
          TradeAssetTransfer.pick(
            draftYear: asset.draftYear,
            overallPick: asset.overallPick,
            originalOwner: career.draftOrder
                .pickAt(asset.overallPick)
                .originalOwnerTeamId,
            from: first.id,
            to: second.id,
          ),
        for (final asset in proposal.picksFromSecond)
          TradeAssetTransfer.pick(
            draftYear: asset.draftYear,
            overallPick: asset.overallPick,
            originalOwner: career.draftOrder
                .pickAt(asset.overallPick)
                .originalOwnerTeamId,
            from: second.id,
            to: first.id,
          ),
        for (final asset in proposal.rightsFromFirst)
          TradeAssetTransfer.rights(
            prospectId: asset.prospectId,
            draftYear: asset.draftYear,
            overallPick: asset.overallPick,
            originalOwner: rightsOriginalOwner(
              career.draftExecutionState.draftRights[asset.prospectId.value] ??
                  career.careerDraftRights[asset.prospectId.value]!,
            ),
            from: first.id,
            to: second.id,
          ),
        for (final asset in proposal.rightsFromSecond)
          TradeAssetTransfer.rights(
            prospectId: asset.prospectId,
            draftYear: asset.draftYear,
            overallPick: asset.overallPick,
            originalOwner: rightsOriginalOwner(
              career.draftExecutionState.draftRights[asset.prospectId.value] ??
                  career.careerDraftRights[asset.prospectId.value]!,
            ),
            from: second.id,
            to: first.id,
          ),
      ],
      firstTeamImpact: (
        capPayrollDelta:
            after.capPayrollFor(first.id, year) -
            before.capPayrollFor(first.id, year),
        cashPayrollDelta:
            after.cashPayrollFor(first.id, year) -
            before.cashPayrollFor(first.id, year),
      ),
    );
    try {
      return career.copyWith(
        league: league,
        finances: after,
        tradeHistory: [...career.tradeHistory, receipt],
        draftOrder: nextDraftOrder,
        draftExecutionState: nextDraftState,
        careerDraftRights: nextCareerRights,
      );
    } on FormatException catch (error) {
      throw PlayerTradeRejected(
        PlayerTradeRejection.invalidCareer,
        detail: error,
      );
    } on DomainValidationException catch (error) {
      throw PlayerTradeRejected(
        PlayerTradeRejection.invalidCareer,
        detail: error,
      );
    }
  }

  static bool _windowOpen(GmCareer career) {
    final draft = career.draftExecutionState;
    final market = career.freeAgentMarket.status;
    return career.phase == CareerPhase.openingOffseason &&
        career.regularSeasonState == null &&
        (draft.isNotStarted ||
            (draft.isCompleted &&
                const RookieAiSigningService()
                    .pendingRights(career)
                    .isEmpty)) &&
        (market == FreeAgentMarketStatus.notStarted ||
            market == FreeAgentMarketStatus.marketComplete) &&
        career.offseasonClearance.status ==
            OffseasonClearanceStatus.notStarted &&
        career.hardshipSettlement.status == HardshipSettlementStatus.notStarted;
  }

  static Team _rosterAfter(
    Team team,
    Set<PlayerId> moved,
    Iterable<_Move> moves,
  ) {
    final incoming = moves.where((m) => m.to == team.id).toList()
      ..sort((a, b) => a.player.id.value.compareTo(b.player.id.value));
    final survivors = team.players.where((p) => !moved.contains(p.id));
    final roster = Roster(
      [...survivors, for (final move in incoming) move.player],
      categories: {
        for (final p in survivors) p.id.value: team.roster.categoryOf(p.id),
        for (final move in incoming)
          move.player.id.value: move.contract.category,
      },
    );
    final validation = roster.validateStructure(
      phase: CareerPhase.openingOffseason,
    );
    if (!validation.isValid) {
      throw PlayerTradeRejected(
        PlayerTradeRejection.rosterLimit,
        teamId: team.id,
        detail: validation.issues,
      );
    }
    return team.copyWith(roster: roster);
  }

  static int minimumRosterReserve(int standardPlayers) =>
      FinancialRules.minimumSalary *
      math.max(0, RosterRules.minRegularSeasonStandard - standardPlayers);

  static void _validateMoney(
    CareerFinances before,
    CareerFinances after,
    Team team,
    int year,
    int lastYear,
    bool draftOnly,
  ) {
    final id = team.id;
    const cap = FinancialRules.salaryCap;
    final oldPayroll = before.capPayrollFor(id, year);
    final newPayroll = after.capPayrollFor(id, year);
    final unchangedGrandfatheredDraftOnly =
        draftOnly &&
        before.financesFor(id).capGrandfathered &&
        newPayroll == oldPayroll;
    if (newPayroll > cap &&
        newPayroll >= oldPayroll &&
        !unchangedGrandfatheredDraftOnly) {
      throw PlayerTradeRejected(
        PlayerTradeRejection.capPayroll,
        teamId: id,
        detail: '$oldPayroll -> $newPayroll ($cap standard cap)',
      );
    }
    final reserve = minimumRosterReserve(team.roster.standardCount);
    final netCash =
        after.projectedEndOfSeasonCash(id, year) - after.debtFor(id);
    if (netCash < reserve) {
      throw PlayerTradeRejected(
        PlayerTradeRejection.cashReserve,
        teamId: id,
        detail: '$netCash available, $reserve required',
      );
    }
    final tf = before.financesFor(id);
    var oldGrandfathered = tf.capGrandfathered;
    var newGrandfathered = tf.capGrandfathered;
    final grandfatheredCeiling =
        tf.grandfatheredPayroll + FinancialRules.maximumReliefOverage;
    for (var future = year + 1; future <= lastYear; future++) {
      final old = before.capPayrollFor(id, future);
      final next = after.capPayrollFor(id, future);
      oldGrandfathered &= old > cap;
      newGrandfathered &= next > cap;
      final oldOverage = math.max(
        0,
        old - (oldGrandfathered ? grandfatheredCeiling : cap),
      );
      final newOverage = math.max(
        0,
        next - (newGrandfathered ? grandfatheredCeiling : cap),
      );
      if (newOverage > oldOverage) {
        throw PlayerTradeRejected(
          PlayerTradeRejection.futureCapPayroll,
          teamId: id,
          detail: 'year $future scheduled overage $oldOverage -> $newOverage',
        );
      }
    }
  }
}

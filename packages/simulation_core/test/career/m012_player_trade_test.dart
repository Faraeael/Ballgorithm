import 'dart:convert';

import 'package:simulation_core/simulation_core.dart';
import 'package:simulation_core/src/career/trade_record.dart';
import 'package:simulation_core/src/career/trade_service.dart';
import 'package:test/test.dart';

import '../support/career_season_fixtures.dart';

const home = TeamId('team-1');
const away = TeamId('team-2');
Team team(GmCareer career, TeamId id) =>
    career.league.teams.firstWhere((t) => t.id == id);
PlayerContract employment(GmCareer career, PlayerId id) =>
    career.finances.contractForPlayer(id)!;
PlayerTradeAsset asset(GmCareer career, PlayerId id) =>
    (playerId: id, contractId: employment(career, id).id);
PlayerTradeProposal proposal(
  GmCareer career,
  List<PlayerTradeAsset> a,
  List<PlayerTradeAsset> b, {
  TeamId first = home,
  TeamId second = away,
}) => PlayerTradeProposal(
  careerId: career.id,
  seasonYear: career.currentYear,
  expectedTradeCount: career.tradeHistory.length,
  firstTeam: first,
  secondTeam: second,
  fromFirst: a,
  fromSecond: b,
);

Iterable<PlayerTradeProposal> proposals(
  GmCareer career, {
  PlayerId? outgoing,
  int count = 1,
}) sync* {
  for (final other in career.league.teams.where((t) => t.id != home)) {
    for (final a in career.userTeam.roster.standardPlayers) {
      if (outgoing != null && a.id != outgoing) continue;
      for (final b in other.roster.standardPlayers) {
        yield proposal(
          career,
          [
            asset(career, a.id),
            if (count == 2)
              asset(
                career,
                career.userTeam.roster.standardPlayers
                    .firstWhere((p) => p.id != a.id)
                    .id,
              ),
          ],
          [asset(career, b.id)],
          second: other.id,
        );
      }
    }
  }
}

(GmCareer, PlayerTradeProposal) legal(
  GmCareer before, {
  PlayerId? outgoing,
  int count = 1,
}) {
  for (final p in proposals(before, outgoing: outgoing, count: count)) {
    try {
      return (PlayerTradeService.buildCandidate(before, p), p);
    } on PlayerTradeRejected catch (e) {
      if (e.reason == PlayerTradeRejection.invalidCareer) rethrow;
    }
  }
  throw StateError('No legal exchange in fixture');
}

Matcher rejects(PlayerTradeRejection reason, [TeamId? side]) => throwsA(
  isA<PlayerTradeRejected>()
      .having((e) => e.reason, 'reason', reason)
      .having((e) => side == null || e.teamId == side, 'side', true),
);

Map<String, Object?> snapshotTerms(GmCareer c, String id) {
  return {
    'employment': c.finances.contracts[id]!.toJson()..remove('teamId'),
    'schedule': c.finances.schedules[id]!.toJson()..remove('teamId'),
  };
}

void expectConservation(
  GmCareer before,
  GmCareer after,
  PlayerTradeProposal p,
) {
  List<String> ids(GmCareer c) => [
    for (final t in c.league.teams)
      for (final player in t.players) player.id.value,
  ]..sort();
  expect(ids(after), ids(before));
  expect(after.finances.contracts.keys, before.finances.contracts.keys);
  expect(after.finances.schedules.keys, before.finances.schedules.keys);
  expect(
    after.finances.guaranteedLiabilities,
    before.finances.guaranteedLiabilities,
  );
  expect(after.finances.staffCommitments, before.finances.staffCommitments);
  expect(after.finances.facilities, before.finances.facilities);
  expect(after.finances.debtByTeam, before.finances.debtByTeam);
  expect(after.finances.teamFinances, before.finances.teamFinances);
  for (final (to, outgoing) in [
    (p.secondTeam, p.fromFirst),
    (p.firstTeam, p.fromSecond),
  ]) {
    for (final moved in outgoing) {
      final old = employment(before, moved.playerId);
      final now = employment(after, moved.playerId);
      expect(now.teamId, to);
      expect(now.id, old.id);
      expect(snapshotTerms(after, old.id), snapshotTerms(before, old.id));
      expect(team(after, to).roster.categoryOf(moved.playerId), old.category);
      for (
        var year = before.currentYear;
        year < old.startYear + old.durationYears;
        year++
      ) {
        expect(
          after.finances.schedules[now.id]!.salaryForYear(year),
          before.finances.schedules[old.id]!.salaryForYear(year),
        );
      }
    }
  }
}

GmCareer changeMoney(
  GmCareer c,
  List<TeamFinances> teams, {
  List<GuaranteedLiability>? liabilities,
}) {
  final f = c.finances;
  return c.copyWith(
    finances: CareerFinances(
      contracts: f.contracts.values,
      schedules: f.schedules.values,
      teamFinances: [
        for (final old in f.teamFinances.values)
          teams
                  .where((replacement) => replacement.teamId == old.teamId)
                  .firstOrNull ??
              old,
      ],
      staffCommitments: f.staffCommitments.values,
      facilities: f.facilities.values,
      guaranteedLiabilities:
          liabilities ?? f.guaranteedLiabilities.values.toList(),
      debtByTeam: f.debtByTeam,
    ),
  );
}

void main() {
  late GmCareer opening;
  late GmCareer preFa;
  setUpAll(() {
    opening = GmCareer.fromSetupResult(
      const CareerSetupService().generate(
        const CareerSetupRequest(
          selectedTeamId: home,
          selectedSituation: FranchiseSituation.tanking,
          seed: 20261028,
        ),
      ),
    );
    preFa = preFreeAgencyOffseason();
  });

  test('one-for-one is atomic, conserved, canonical and persists in v28', () {
    final original = GmCareerCodec.encode(opening);
    final (next, p) = legal(opening);
    expectConservation(opening, next, p);
    final receipt = next.tradeHistory.single;
    expect(receipt.id, 'trade-1-1');
    expect(receipt.phase, CareerPhase.openingOffseason);
    expect(
      receipt.firstTeamImpact.capPayrollDelta,
      next.finances.capPayrollFor(home, 1) -
          opening.finances.capPayrollFor(home, 1),
    );
    expect(
      receipt.firstTeamImpact.cashPayrollDelta,
      next.finances.cashPayrollFor(home, 1) -
          opening.finances.cashPayrollFor(home, 1),
    );
    expect(next.copyWith().tradeHistory.single, same(receipt));
    final encoded = GmCareerCodec.encode(next);
    expect(
      GmCareerCodec.decode(encoded).tradeHistory.single.toJson(),
      receipt.toJson(),
    );
    expect(
      () => PlayerTradeService.buildCandidate(next, p),
      rejects(PlayerTradeRejection.staleProposal),
    );
    final reverse = proposal(
      next,
      p.fromSecond,
      p.fromFirst,
      second: p.secondTeam,
    );
    expect(
      () => PlayerTradeService.buildCandidate(next, reverse),
      rejects(PlayerTradeRejection.alreadyTraded),
    );
    expect(GmCareerCodec.encode(opening), original);
    expect(GmCareerCodec.encode(GmCareerCodec.decode(original)), original);
    final current = jsonDecode(original) as Map<String, dynamic>;
    expect(current['schemaVersion'], 29);
    expect(current['tradeHistory'], isEmpty);
    final v27 = Map<String, dynamic>.of(current)
      ..['schemaVersion'] = 27
      ..remove('tradeHistory')
      ..remove('emergencySettlement');
    expect(GmCareerCodec.decode(jsonEncode(v27)).tradeHistory, isEmpty);
    expect(
      () => GmCareerCodec.decode(jsonEncode({...v27, 'tradeHistory': []})),
      throwsFormatException,
    );
    final future = Map<String, dynamic>.of(current)..['schemaVersion'] = 30;
    expect(
      () => GmCareerCodec.decode(jsonEncode(future)),
      throwsFormatException,
    );
  });

  test(
    'multi-player changes only participating rosters and supports offseason shortages',
    () {
      final (next, p) = legal(opening, count: 2);
      expectConservation(opening, next, p);
      expect(next.userTeam.roster.standardCount, 11);
      expect(team(next, p.secondTeam).roster.standardCount, 13);
      expect(next.tradeHistory.single.transfers, hasLength(3));
      expect(
        () => const RegularSeasonEntryService().start(next),
        throwsA(anything),
      );
      final sender = opening.userTeam.players.where(
        (x) => !p.fromFirst.any((a) => a.playerId == x.id),
      );
      expect(next.userTeam.players.take(sender.length), sender);
      for (final other in opening.league.teams.where(
        (t) => t.id != home && t.id != p.secondTeam,
      )) {
        expect(team(next, other.id), same(other));
      }
    },
  );

  test(
    'invalid participants, empty side, duplicates, stale ownership and contract are rejected',
    () {
      final a = asset(opening, opening.userTeam.players.first.id);
      final b = asset(opening, team(opening, away).players.first.id);
      final original = GmCareerCodec.encode(opening);
      void check(PlayerTradeProposal p, PlayerTradeRejection r) => expect(
        () => PlayerTradeService.buildCandidate(opening, p),
        rejects(r),
      );
      check(
        proposal(opening, [a], [b], second: home),
        PlayerTradeRejection.invalidFranchises,
      );
      check(proposal(opening, [], [b]), PlayerTradeRejection.emptySide);
      check(proposal(opening, [a], [a]), PlayerTradeRejection.duplicateAsset);
      check(proposal(opening, [b], [a]), PlayerTradeRejection.staleOwnership);
      check(
        proposal(opening, [(playerId: a.playerId, contractId: 'wrong')], [b]),
        PlayerTradeRejection.staleContract,
      );
      expect(GmCareerCodec.encode(opening), original);
      expect(opening.tradeHistory, isEmpty);
    },
  );

  test('draft, open market, clearance and regular season lock transactions', () {
    const market = FreeAgentMarketService();
    final draft = const DraftExecutionService().startDraft(opening);
    final open = market.startRound(preFa);
    var complete = preFa;
    for (var i = 0; i < 2; i++) {
      complete = market.prepareResolution(market.startRound(complete));
      while (complete.freeAgentMarket.isResolvable) {
        complete = market.resolveNext(complete);
      }
    }
    final cleared = clearOffseason(preFa);
    for (final c in [
      draft,
      open,
      const OffseasonClearanceService().start(complete),
      const RegularSeasonEntryService().start(cleared),
    ]) {
      final p = proposals(c).first;
      final before = GmCareerCodec.encode(c);
      expect(
        () => PlayerTradeService.buildCandidate(c, p),
        rejects(PlayerTradeRejection.windowClosed),
      );
      expect(GmCareerCodec.encode(c), before);
    }
    // Market completed before clearance: a same-year signing can move, but its
    // acquisition and offer evidence still belong to the original franchise.
    for (final acq in complete.freeAgentPool.acquisitions.entries.values.where(
      (a) => a.teamId != home,
    )) {
      for (final candidate in complete.userTeam.players) {
        final p = proposal(
          complete,
          [asset(complete, candidate.id)],
          [asset(complete, acq.playerId)],
          second: acq.teamId,
        );
        GmCareer next;
        try {
          next = PlayerTradeService.buildCandidate(complete, p);
        } on PlayerTradeRejected catch (e) {
          if (e.reason == PlayerTradeRejection.invalidCareer) rethrow;
          continue;
        }
        expectConservation(complete, next, p);
        expect(
          next.freeAgentPool.acquisitions,
          same(complete.freeAgentPool.acquisitions),
        );
        expect(next.freeAgentMarket, same(complete.freeAgentMarket));
        expect(next.freeAgentOffers, same(complete.freeAgentOffers));
        return;
      }
    }
    fail('No legal same-year FA exchange in completed market fixture');
  });

  test(
    'rookie provenance and retained manual/coach state survive; forged receipt fails',
    () {
      final roster = RegularSeasonGameAdapter.standardTeamFor(preFa.userTeam);
      final rookie = preFa.rookieSigningLedger.contracts.values.firstWhere(
        (r) => r.teamId == home && r.category == RosterCategory.standard,
      );
      final defaults = CourtLineup.defaultFor(
        roster,
      ).playerIds.map(PlayerId.new).toList();
      if (!defaults.contains(rookie.playerId)) defaults[0] = rookie.playerId;
      final manual = CareerRotationSettings.manual(
        starters: defaults,
        preset: RotationPreset.custom,
        customTargets: {
          for (final p in roster.players)
            p.id.value: defaults.contains(p.id) ? 2880 : 0,
        },
      );
      final enabled = const StaffMarketService().enableCoaching(preFa);
      final start = enabled.copyWith(
        userRotation: CareerRotationSettings.autoRetaining(manual),
      );
      final (next, p) = legal(start, outgoing: rookie.playerId);
      expectConservation(start, next, p);
      expect(next.rookieSigningLedger.forPlayer(rookie.playerId), same(rookie));
      expect(next.draftExecutionState, same(start.draftExecutionState));
      expect(next.userRotation.retainedManual, same(manual));
      final decision = CareerRotationService.decisionForUser(next);
      expect(decision.authority, RotationAuthority.headCoach);
      expect(decision.plan.targetSeconds.containsKey(rookie.playerId), isFalse);
      final obsolete = next.copyWith(userRotation: manual);
      final resolution = CareerRotationService.resolveForCareer(obsolete);
      expect(
        resolution.issues.map((i) => i.code),
        containsAll([
          CareerRotationIssueCode.starterUnavailable,
          CareerRotationIssueCode.targetPlayerUnavailable,
        ]),
      );
      expect(
        resolution.unassignedPlayerIds,
        contains(p.fromSecond.single.playerId),
      );
      expect(obsolete.userRotation.customTargets[rookie.playerId.value], 2880);
      expect(
        () => next.copyWith(tradeHistory: const []),
        throwsFormatException,
      );
      final record = next.tradeHistory.single;
      final forged = TradeRecord(
        seasonYear: record.seasonYear,
        sequence: record.sequence,
        firstTeam: record.firstTeam,
        secondTeam: record.secondTeam,
        firstTeamImpact: record.firstTeamImpact,
        transfers: [
          for (final t in record.transfers)
            (
              playerId: t.playerId,
              contractId: t.contractId,
              from: t.from,
              to: t.to,
              startYear: t.startYear,
              endYear: t.endYear,
              termsDigest: '0' * 64,
            ),
        ],
      );
      expect(
        () => start.copyWith(
          league: next.league,
          finances: next.finances,
          tradeHistory: [forged],
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'post-trade cash reserve validates either side with all operating costs',
    () {
      for (final reverse in [false, true]) {
        const side = home;
        final f = opening.finances;
        final tf = f.financesFor(side);
        final cash = f.projectedEndOfSeasonCash(side, 1);
        final reserve =
            FinancialRules.minimumSalary *
            (14 - team(opening, side).roster.standardCount);
        final squeezed = changeMoney(opening, [
          TeamFinances(
            teamId: side,
            operatingBudget: tf.operatingBudget,
            cash: tf.cash,
            revenueBaseline: tf.revenueBaseline - cash + reserve,
            season: 1,
            capGrandfathered: tf.capGrandfathered,
            grandfatheredPayroll: tf.grandfatheredPayroll,
            capException: tf.capException,
          ),
        ]);
        final other = side == home ? away : home;
        int salary(Player player) =>
            f.scheduleFor(employment(opening, player.id).id)!.salaryForYear(1)!;
        final cheap = team(
          opening,
          side,
        ).players.reduce((x, y) => salary(x) < salary(y) ? x : y);
        final costly = team(
          opening,
          other,
        ).players.reduce((x, y) => salary(x) > salary(y) ? x : y);
        expect(salary(costly), greaterThan(salary(cheap)));
        final p = proposal(
          squeezed,
          [asset(squeezed, (reverse ? costly : cheap).id)],
          [asset(squeezed, (reverse ? cheap : costly).id)],
          first: reverse ? other : side,
          second: reverse ? side : other,
        );
        expect(
          () => PlayerTradeService.buildCandidate(squeezed, p),
          rejects(PlayerTradeRejection.cashReserve, side),
        );
      }
    },
  );

  test(
    'offseason category caps reject a 16th standard player on either side',
    () {
      final h = opening.userTeam.roster.standardPlayers;
      final a = team(opening, away).roster.standardPlayers;
      final many = h.take(5).map((p) => asset(opening, p.id)).toList();
      final one = [asset(opening, a.first.id)];
      for (final reverse in [false, true]) {
        final p = proposal(
          opening,
          reverse ? one : many,
          reverse ? many : one,
          first: reverse ? away : home,
          second: reverse ? home : away,
        );
        expect(
          () => PlayerTradeService.buildCandidate(opening, p),
          rejects(PlayerTradeRejection.rosterLimit, away),
        );
      }
    },
  );

  test(
    'rollover preserves history and grandfathered cap trade boundaries',
    () {
      final finished = completeSeason(scheduledSeason(clearOffseason(preFa)));
      final rollover = const SeasonRolloverService().prepareArchiveAndRollover(
        current: finished,
      );
      final before = rollover.rolloverResult.nextCareer;
      final continuing = before.userTeam.players.firstWhere((p) {
        final c = employment(before, p.id);
        return c.startYear < before.currentYear && c.durationYears >= 2;
      });
      final (after, p) = legal(before, outgoing: continuing.id);
      expectConservation(before, after, p);
      expect(after.seasonHistory.single, same(before.seasonHistory.single));
      expect(after.seasonHistory.single.archiveDigest, rollover.archiveDigest);
      expect(
        after.seasonSettlements.single,
        same(before.seasonSettlements.single),
      );
      expect(after.marketHistory.single, same(before.marketHistory.single));
      // A separately scheduled, existing guarantee makes the current cap
      // boundary precise without modifying the tested player salary schedules.
      GmCareer atCap(TeamId id, int cap, {bool grandfathered = false}) {
        final f = before.finances;
        final old = f.financesFor(id);
        var remaining = cap - f.capPayrollFor(id, 2);
        final liabilities = f.guaranteedLiabilities.values.toList();
        final addition = remaining;
        for (var i = 0; remaining > 0; i++) {
          final amount = remaining > FinancialRules.maximumSalary
              ? FinancialRules.maximumSalary
              : remaining;
          final contract = 't02-boundary-${id.value}-$i';
          liabilities.add(
            GuaranteedLiability(
              id: GuaranteedLiability.idFor(contract),
              originalContractId: contract,
              playerId: PlayerId('retired-$contract'),
              teamId: id,
              originalCategory: RosterCategory.standard,
              retirementYear: 1,
              salariesByYear: {2: amount},
            ),
          );
          remaining -= amount;
        }
        return changeMoney(before, [
          TeamFinances(
            teamId: id,
            season: 2,
            operatingBudget: old.operatingBudget,
            cash: old.cash,
            revenueBaseline: old.revenueBaseline + addition + 2000,
            capGrandfathered: grandfathered,
            grandfatheredPayroll: grandfathered ? cap : 0,
          ),
        ], liabilities: liabilities);
      }

      int currentSalary(PlayerTradeAsset asset) =>
          before.finances.schedules[asset.contractId]!.salaryForYear(2)!;
      final unequal = proposals(before).firstWhere(
        (p) =>
            currentSalary(p.fromSecond.single) >
            currentSalary(p.fromFirst.single),
      );
      final capped = atCap(home, FinancialRules.salaryCap);
      for (final reverse in [false, true]) {
        final request = proposal(
          capped,
          reverse ? unequal.fromSecond : unequal.fromFirst,
          reverse ? unequal.fromFirst : unequal.fromSecond,
          first: reverse ? unequal.secondTeam : home,
          second: reverse ? home : unequal.secondTeam,
        );
        expect(
          () => PlayerTradeService.buildCandidate(capped, request),
          rejects(PlayerTradeRejection.capPayroll, home),
        );
      }
      final releasing = atCap(
        unequal.secondTeam,
        FinancialRules.salaryCap + 100,
        grandfathered: true,
      );
      final reducing = PlayerTradeService.buildCandidate(releasing, unequal);
      expectConservation(releasing, reducing, unequal);
      expect(
        reducing.finances.capPayrollFor(unequal.secondTeam, 2),
        lessThan(releasing.finances.capPayrollFor(unequal.secondTeam, 2)),
      );

      final equal = proposals(before).firstWhere(
        (p) =>
            currentSalary(p.fromFirst.single) ==
            currentSalary(p.fromSecond.single),
      );
      for (final side in [home, equal.secondTeam]) {
        final grandfathered = atCap(
          side,
          FinancialRules.salaryCap + 100,
          grandfathered: true,
        );
        final baseline = grandfathered.finances.capPayrollFor(side, 2);
        expect(baseline, greaterThan(FinancialRules.salaryCap));
        expect(
          GmCareerCodec.decode(
            GmCareerCodec.encode(grandfathered),
          ).finances.capPayrollFor(side, 2),
          baseline,
        );
        final increasing = proposals(before).firstWhere(
          (p) =>
              p.secondTeam == equal.secondTeam &&
              (side == home
                  ? currentSalary(p.fromSecond.single) >
                        currentSalary(p.fromFirst.single)
                  : currentSalary(p.fromFirst.single) >
                        currentSalary(p.fromSecond.single)),
        );
        final firstPick = grandfathered.draftOrder.picks.firstWhere(
          (pick) => pick.currentOwnerTeamId == home,
        );
        final secondPick = grandfathered.draftOrder.picks.firstWhere(
          (pick) => pick.currentOwnerTeamId == equal.secondTeam,
        );
        for (final reverse in [false, true]) {
          final first = reverse ? equal.secondTeam : home;
          final second = reverse ? home : equal.secondTeam;
          final pickTrade = PlayerTradeProposal(
            careerId: grandfathered.id,
            seasonYear: grandfathered.currentYear,
            expectedTradeCount: grandfathered.tradeHistory.length,
            firstTeam: first,
            secondTeam: second,
            picksFromFirst: [
              (
                draftYear: 2,
                overallPick: reverse
                    ? secondPick.overallPick
                    : firstPick.overallPick,
                expectedOwner: first,
              ),
            ],
            picksFromSecond: [
              (
                draftYear: 2,
                overallPick: reverse
                    ? firstPick.overallPick
                    : secondPick.overallPick,
                expectedOwner: second,
              ),
            ],
          );
          final traded = PlayerTradeService.buildCandidate(
            grandfathered,
            pickTrade,
          );
          expect(traded.finances.capPayrollFor(side, 2), baseline);
          expect(
            traded.draftOrder.pickAt(firstPick.overallPick).currentOwnerTeamId,
            equal.secondTeam,
          );
          expect(
            traded.draftOrder.pickAt(secondPick.overallPick).currentOwnerTeamId,
            home,
          );
          final playerTrade = proposal(
            grandfathered,
            reverse ? equal.fromSecond : equal.fromFirst,
            reverse ? equal.fromFirst : equal.fromSecond,
            first: first,
            second: second,
          );
          expect(
            () => PlayerTradeService.buildCandidate(grandfathered, playerTrade),
            rejects(PlayerTradeRejection.capPayroll, side),
          );
          final increasedPayroll = proposal(
            grandfathered,
            reverse ? increasing.fromSecond : increasing.fromFirst,
            reverse ? increasing.fromFirst : increasing.fromSecond,
            first: first,
            second: second,
          );
          expect(
            () => PlayerTradeService.buildCandidate(
              grandfathered,
              increasedPayroll,
            ),
            rejects(PlayerTradeRejection.capPayroll, side),
          );
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

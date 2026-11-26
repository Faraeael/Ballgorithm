import 'package:simulation_core/simulation_core.dart';
import 'package:simulation_core/src/career/trade_service.dart';
import 'package:test/test.dart';

const user = TeamId('team-1');

int pickValue(int slot) => switch (slot) {
  <= 5 => 96,
  <= 14 => 64,
  <= 30 => 36,
  <= 45 => 14,
  _ => 5,
};

PlayerTradeProposal pickOffer(
  GmCareer career,
  Team opponent,
  Iterable<DraftPick> offered,
  DraftPick requested,
) => PlayerTradeProposal(
  careerId: career.id,
  seasonYear: career.currentYear,
  expectedTradeCount: career.tradeHistory.length,
  firstTeam: user,
  secondTeam: opponent.id,
  picksFromFirst: [
    for (final pick in offered)
      (
        draftYear: career.currentYear,
        overallPick: pick.overallPick,
        expectedOwner: user,
      ),
  ],
  picksFromSecond: [
    (
      draftYear: career.currentYear,
      overallPick: requested.overallPick,
      expectedOwner: opponent.id,
    ),
  ],
);

GmCareer controlledCareer(
  GmCareer career, {
  required TeamId aiTeamId,
  required Map<PlayerId, int> ratings,
  Map<PlayerId, int> ages = const {},
}) {
  final highTeams = {for (var i = 3; i <= 10; i++) TeamId('team-$i')};
  final ratingByPlayer = <PlayerId, int>{};
  int ratingFor(Team team, Player player) =>
      ratings[player.id] ??
      (team.id == user
          ? 60
          : team.id == aiTeamId
          ? 55
          : highTeams.contains(team.id)
          ? 80
          : 40);
  Player updatePlayer(Team team, Player player) {
    final rating = ratingFor(team, player);
    ratingByPlayer[player.id] = rating;
    return Player(
      id: player.id,
      firstName: player.firstName,
      lastName: player.lastName,
      position: player.position,
      attributes: PlayerAttributes(
        insideScoring: rating,
        midrange: rating,
        threePoint: rating,
        freeThrow: rating,
        passing: rating,
        ballHandling: rating,
        perimeterDefense: rating,
        interiorDefense: rating,
        rebounding: rating,
        athleticism: rating,
        stamina: rating,
        basketballIQ: rating,
      ),
    );
  }

  final teams = [
    for (final team in career.league.teams)
      team.copyWith(
        roster: Roster([
          for (final player in team.players) updatePlayer(team, player),
        ], categories: team.roster.categories),
      ),
  ];
  final profiles = {
    for (final entry in career.careerProfiles.profiles.entries)
      entry.key: PlayerCareerProfile(
        playerId: entry.value.playerId,
        age: ages[entry.value.playerId] ?? 28,
        potential:
            (ratingByPlayer[entry.value.playerId] ?? entry.value.potential) >
                entry.value.potential
            ? ratingByPlayer[entry.value.playerId]!
            : entry.value.potential,
        trajectory: entry.value.trajectory,
      ),
  };
  return career.copyWith(
    league: League.create(
      id: career.league.id,
      name: career.league.name,
      config: career.league.config,
      teams: teams,
    ),
    careerProfiles: LeagueCareerProfiles(
      schemaVersion: career.careerProfiles.schemaVersion,
      leagueSeed: career.careerProfiles.leagueSeed,
      profiles: profiles,
    ),
  );
}

CareerFinances withOneYearSalaries(GmCareer career, Map<String, int> salaries) {
  final finances = career.finances;
  return CareerFinances(
    contracts: [
      for (final contract in finances.contracts.values)
        if (salaries.containsKey(contract.id))
          PlayerContract(
            id: contract.id,
            playerId: contract.playerId,
            teamId: contract.teamId,
            category: contract.category,
            startYear: career.currentYear,
            durationYears: 1,
            source: ContractSource.freeAgent,
          )
        else
          contract,
    ],
    schedules: [
      for (final schedule in finances.schedules.values)
        if (salaries.containsKey(schedule.contractId))
          ContractFinancials(
            contractId: schedule.contractId,
            playerId: schedule.playerId,
            teamId: schedule.teamId,
            annualSalaries: [salaries[schedule.contractId]!],
            guaranteedYears: 1,
            source: ContractSource.freeAgent,
            signedYear: career.currentYear,
          )
        else
          schedule,
    ],
    teamFinances: finances.teamFinances.values,
    staffCommitments: finances.staffCommitments.values,
    facilities: finances.facilities.values,
    guaranteedLiabilities: finances.guaranteedLiabilities.values,
    debtByTeam: finances.debtByTeam,
  );
}

PlayerTradeProposal playerOffer(
  GmCareer career,
  TeamId aiTeam,
  Iterable<Player> offered,
  Player requested,
) => PlayerTradeProposal(
  careerId: career.id,
  seasonYear: career.currentYear,
  expectedTradeCount: career.tradeHistory.length,
  firstTeam: user,
  secondTeam: aiTeam,
  fromFirst: [
    for (final player in offered)
      (
        playerId: player.id,
        contractId: career.finances.contractForPlayer(player.id)!.id,
      ),
  ],
  fromSecond: [
    (
      playerId: requested.id,
      contractId: career.finances.contractForPlayer(requested.id)!.id,
    ),
  ],
);

void main() {
  late GmCareer career;
  setUpAll(
    () => career = GmCareer.fromSetupResult(
      const CareerSetupService().generate(
        const CareerSetupRequest(
          selectedTeamId: user,
          selectedSituation: FranchiseSituation.tanking,
          seed: 20261028,
        ),
      ),
    ),
  );

  test(
    'evaluation is deterministic, read-only, accepted quotes execute once',
    () {
      final userPicks = career.draftOrder.picks
          .where((pick) => pick.currentOwnerTeamId == user)
          .toList();
      final opportunities = <(Team, DraftPick, int)>[];
      for (final team in career.league.teams.where((t) => t.id != user)) {
        for (final pick in career.draftOrder.picks.where(
          (pick) => pick.currentOwnerTeamId == team.id,
        )) {
          final gain =
              userPicks.fold<int>(
                0,
                (sum, offered) => sum + pickValue(offered.overallPick),
              ) -
              pickValue(pick.overallPick);
          opportunities.add((team, pick, gain));
        }
      }
      opportunities.sort((a, b) => b.$3.compareTo(a.$3));
      final (opponent, requested, gain) = opportunities.first;
      expect(gain, greaterThan(6));
      final proposal = pickOffer(career, opponent, userPicks, requested);
      final before = GmCareerCodec.encode(career);
      final first = TradeOfferService.evaluate(career, proposal);
      final again = TradeOfferService.evaluate(career, proposal);
      expect(GmCareerCodec.encode(career), before);
      expect(first.status, TradeOfferStatus.legalAccepted);
      expect(first.valuation!.accepted, isTrue);
      expect(first.valuation!.draft, gain);
      expect(again.status, first.status);
      expect(again.valuation!.score, first.valuation!.score);
      expect(again.valuation!.strategy, first.valuation!.strategy);

      final next = TradeOfferService.executeAccepted(career, proposal, first);
      expect(next.tradeHistory, hasLength(1));
      expect(
        GmCareerCodec.decode(GmCareerCodec.encode(next)).tradeHistory,
        hasLength(1),
      );
      expect(
        () => TradeOfferService.executeAccepted(next, proposal, first),
        throwsA(isA<TradeQuoteRejected>()),
      );
      expect(GmCareerCodec.encode(career), before);
    },
  );

  test('equal-band pick exchange is legal but rejected by strategy margin', () {
    final userPick = career.draftOrder.picks.firstWhere(
      (pick) => pick.currentOwnerTeamId == user,
    );
    final band = pickValue(userPick.overallPick);
    final opponent = career.league.teams.firstWhere(
      (team) =>
          team.id != user &&
          career.draftOrder.picks.any(
            (pick) =>
                pick.currentOwnerTeamId == team.id &&
                pickValue(pick.overallPick) == band,
          ),
    );
    final requested = career.draftOrder.picks.firstWhere(
      (pick) =>
          pick.currentOwnerTeamId == opponent.id &&
          pickValue(pick.overallPick) == band,
    );
    final proposal = pickOffer(career, opponent, [userPick], requested);
    final quote = TradeOfferService.evaluate(career, proposal);
    expect(quote.status, TradeOfferStatus.legalRejected);
    expect(quote.teamPreviews, hasLength(2));
    expect(quote.valuation!.draft, 0);
    expect(quote.valuation!.accepted, isFalse);
    expect(
      TradeOfferService.evaluate(career, proposal).valuation!.score,
      quote.valuation!.score,
    );
  });

  test('accepted margin changes by the AI franchise strategy', () {
    final userPick = career.draftOrder.picks.firstWhere(
      (pick) =>
          pick.currentOwnerTeamId == user && pickValue(pick.overallPick) == 14,
    );
    final requested = career.draftOrder.picks.firstWhere(
      (pick) =>
          pick.currentOwnerTeamId != user && pickValue(pick.overallPick) == 5,
    );
    final ai = career.league.teams.firstWhere(
      (team) => team.id == requested.currentOwnerTeamId,
    );
    final proposal = pickOffer(career, ai, [userPick], requested);
    final rankings = <FranchiseTradeStrategy, Map<PlayerId, int>>{};
    for (final strategy in FranchiseTradeStrategy.values) {
      final ranking = switch (strategy) {
        FranchiseTradeStrategy.contending => {
          for (final team in career.league.teams)
            for (final player in team.players)
              player.id: team.id == ai.id ? 90 : 80,
        },
        FranchiseTradeStrategy.middle => {
          for (final team in career.league.teams)
            for (final player in team.players)
              player.id: team.id == ai.id
                  ? 70
                  : team.id == user
                  ? 80
                  : career.league.teams
                        .where(
                          (candidate) =>
                              candidate.id != ai.id && candidate.id != user,
                        )
                        .take(14)
                        .any((candidate) => candidate.id == team.id)
                  ? 90
                  : 40,
        },
        FranchiseTradeStrategy.rebuilding => {
          for (final team in career.league.teams)
            for (final player in team.players)
              player.id: team.id == ai.id ? 40 : 80,
        },
      };
      rankings[strategy] = ranking;
    }
    final middle = TradeOfferService.evaluate(
      controlledCareer(
        career,
        aiTeamId: ai.id,
        ratings: rankings[FranchiseTradeStrategy.middle]!,
      ),
      proposal,
    );
    final contender = TradeOfferService.evaluate(
      controlledCareer(
        career,
        aiTeamId: ai.id,
        ratings: rankings[FranchiseTradeStrategy.contending]!,
      ),
      proposal,
    );
    final rebuilder = TradeOfferService.evaluate(
      controlledCareer(
        career,
        aiTeamId: ai.id,
        ratings: rankings[FranchiseTradeStrategy.rebuilding]!,
      ),
      proposal,
    );
    expect(middle.valuation!.strategy, FranchiseTradeStrategy.middle);
    expect(middle.valuation!.draft, 9);
    expect(middle.valuation!.score, 9);
    expect(middle.status, TradeOfferStatus.legalAccepted);
    expect(contender.valuation!.strategy, FranchiseTradeStrategy.contending);
    expect(contender.valuation!.score, 6);
    expect(contender.status, TradeOfferStatus.legalRejected);
    expect(rebuilder.valuation!.strategy, FranchiseTradeStrategy.rebuilding);
    expect(rebuilder.valuation!.score, 13);
    expect(rebuilder.status, TradeOfferStatus.legalAccepted);
  });

  test('rebuilding values efficient future years for a younger player', () {
    final pairs =
        <
          ({
            Team ai,
            Player younger,
            Player older,
            int control,
            int salaryDifference,
          })
        >[];
    for (final ai in career.league.teams.where((team) => team.id != user)) {
      for (final younger in career.userTeam.roster.standardPlayers) {
        final youngContract = career.finances.contractForPlayer(younger.id)!;
        final youngSchedule = career.finances.scheduleFor(youngContract.id)!;
        final futureYears = [
          for (
            var year = career.currentYear + 1;
            year <= career.currentYear + 4;
            year++
          )
            if (youngSchedule.salaryForYear(year) case final salary?
                when salary <= 4000)
              year,
        ];
        if (futureYears.isEmpty) continue;
        for (final older in ai.roster.standardPlayers) {
          if (younger.position != older.position) continue;
          final oldContract = career.finances.contractForPlayer(older.id)!;
          final oldSchedule = career.finances.scheduleFor(oldContract.id)!;
          var salaryDifference = 0;
          for (
            var year = career.currentYear;
            year <= career.currentYear + 4;
            year++
          ) {
            salaryDifference +=
                ((youngSchedule.salaryForYear(year) ?? 0) -
                        (oldSchedule.salaryForYear(year) ?? 0))
                    .abs();
          }
          pairs.add((
            ai: ai,
            younger: younger,
            older: older,
            control: futureYears.length * 6,
            salaryDifference: salaryDifference,
          ));
        }
      }
    }
    pairs.sort((a, b) => a.salaryDifference.compareTo(b.salaryDifference));
    TradeOfferQuote? quote;
    var expectedControl = 0;
    for (final pair in pairs) {
      final ratings = {
        for (final team in career.league.teams)
          for (final player in team.players)
            player.id: team.id == pair.ai.id
                ? 40
                : team.id == user
                ? 60
                : 80,
        pair.younger.id: 90,
        pair.older.id: 90,
      };
      final controlled = controlledCareer(
        career,
        aiTeamId: pair.ai.id,
        ratings: ratings,
        ages: {pair.younger.id: 21, pair.older.id: 29},
      );
      final proposal = playerOffer(
        controlled,
        pair.ai.id,
        [
          controlled.userTeam.players.firstWhere(
            (player) => player.id == pair.younger.id,
          ),
        ],
        controlled.league.teams
            .firstWhere((team) => team.id == pair.ai.id)
            .players
            .firstWhere((player) => player.id == pair.older.id),
      );
      final candidateQuote = TradeOfferService.evaluate(controlled, proposal);
      if (candidateQuote.status == TradeOfferStatus.legalAccepted) {
        quote = candidateQuote;
        expectedControl = pair.control;
        break;
      }
    }
    expect(quote, isNotNull);
    final acceptedQuote = quote!;
    expect(acceptedQuote.status, TradeOfferStatus.legalAccepted);
    expect(
      acceptedQuote.valuation!.strategy,
      FranchiseTradeStrategy.rebuilding,
    );
    expect(acceptedQuote.valuation!.control, expectedControl);
    expect(acceptedQuote.valuation!.control, greaterThan(0));
    expect(acceptedQuote.valuation!.basketball, 0);
    expect(acceptedQuote.valuation!.draft, 0);
  });

  test('approved middle-tier plus-two exchange scores exactly eight', () {
    final ai = career.league.teams.firstWhere(
      (team) => team.id == TeamId('team-2'),
    );
    final userTeam = career.userTeam;
    late Player userPlayer;
    late Player aiPlayer;
    var found = false;
    for (final candidate in userTeam.roster.standardPlayers) {
      final userContract = career.finances.contractForPlayer(candidate.id)!;
      final userSchedule = career.finances.scheduleFor(userContract.id)!;
      for (final opponent in ai.roster.standardPlayers) {
        final aiContract = career.finances.contractForPlayer(opponent.id)!;
        final aiSchedule = career.finances.scheduleFor(aiContract.id)!;
        final aiDepth = ai.roster.standardPlayers
            .where((player) => player.position == opponent.position)
            .length;
        if (candidate.position == opponent.position &&
            aiDepth >= 2 &&
            userContract.startYear == aiContract.startYear &&
            userContract.durationYears == aiContract.durationYears &&
            userSchedule.signedYear == aiSchedule.signedYear &&
            userSchedule.guaranteedYears == aiSchedule.guaranteedYears &&
            userSchedule.annualSalaries.join(',') ==
                aiSchedule.annualSalaries.join(',')) {
          userPlayer = candidate;
          aiPlayer = opponent;
          found = true;
          break;
        }
      }
      if (found) break;
    }
    expect(found, isTrue);
    final controlled = controlledCareer(
      career,
      aiTeamId: ai.id,
      ratings: {userPlayer.id: 72, aiPlayer.id: 70},
    );
    final proposal = playerOffer(
      controlled,
      ai.id,
      [controlled.userTeam.players.firstWhere((p) => p.id == userPlayer.id)],
      controlled.league.teams
          .firstWhere((t) => t.id == ai.id)
          .players
          .firstWhere((p) => p.id == aiPlayer.id),
    );
    final quote = TradeOfferService.evaluate(controlled, proposal);
    expect(quote.status, TradeOfferStatus.legalAccepted);
    final next = TradeOfferService.executeAccepted(controlled, proposal, quote);
    expect(quote.teamPreviews.keys, containsAll([user, ai.id]));
    for (final id in [user, ai.id]) {
      final preview = quote.teamPreviews[id]!;
      final beforeTeam = controlled.league.teams.firstWhere((t) => t.id == id);
      final afterTeam = next.league.teams.firstWhere((t) => t.id == id);
      expect(
        preview.capPayrollBefore,
        controlled.finances.capPayrollFor(id, 1),
      );
      expect(preview.capPayrollAfter, next.finances.capPayrollFor(id, 1));
      expect(
        preview.cashPayrollBefore,
        controlled.finances.cashPayrollFor(id, 1),
      );
      expect(preview.cashPayrollAfter, next.finances.cashPayrollFor(id, 1));
      expect(
        preview.projectedCashAfterDebtBefore,
        controlled.finances.projectedEndOfSeasonCash(id, 1) -
            controlled.finances.debtFor(id),
      );
      expect(
        preview.projectedCashAfterDebtAfter,
        next.finances.projectedEndOfSeasonCash(id, 1) -
            next.finances.debtFor(id),
      );
      expect(preview.standardPlayersBefore, beforeTeam.roster.standardCount);
      expect(preview.standardPlayersAfter, afterTeam.roster.standardCount);
      expect(preview.twoWayPlayersBefore, beforeTeam.roster.twoWayCount);
      expect(preview.twoWayPlayersAfter, afterTeam.roster.twoWayCount);
      expect(
        preview.minimumRosterReserveBefore,
        PlayerTradeService.minimumRosterReserve(
          beforeTeam.roster.standardCount,
        ),
      );
      expect(
        preview.minimumRosterReserveAfter,
        PlayerTradeService.minimumRosterReserve(afterTeam.roster.standardCount),
      );
    }
    expect(quote.valuation!.strategy, FranchiseTradeStrategy.middle);
    expect(quote.valuation!.basketball, 8);
    expect(quote.valuation!.control, 0);
    expect(quote.valuation!.finance, 0);
    expect(quote.valuation!.draft, 0);
    expect(quote.valuation!.score, 8);
    expect(quote.valuation!.threshold, 6);
  });

  test('strategy margins reject ties and accept only higher scores', () {
    final ai = career.league.teams.firstWhere(
      (team) => team.id == TeamId('team-2'),
    );
    late Player opponent;
    late Player incoming;
    var found = false;
    for (final candidate in ai.roster.standardPlayers.skip(5)) {
      if (ai.roster.standardPlayers
              .where((other) => other.position == candidate.position)
              .length <
          2) {
        continue;
      }
      final candidateContract = career.finances.contractForPlayer(
        candidate.id,
      )!;
      final candidateSchedule = career.finances.scheduleFor(
        candidateContract.id,
      )!;
      for (final player in career.userTeam.roster.standardPlayers) {
        final contract = career.finances.contractForPlayer(player.id)!;
        final schedule = career.finances.scheduleFor(contract.id)!;
        if (player.position == candidate.position &&
            schedule.signedYear == candidateSchedule.signedYear &&
            schedule.annualSalaries.length ==
                candidateSchedule.annualSalaries.length &&
            schedule.guaranteedYears == candidateSchedule.guaranteedYears) {
          opponent = candidate;
          incoming = player;
          found = true;
          break;
        }
      }
      if (found) break;
    }
    expect(found, isTrue);
    final incomingContract = career.finances.contractForPlayer(incoming.id)!;
    final outgoingContract = career.finances.contractForPlayer(opponent.id)!;
    for (final strategy in FranchiseTradeStrategy.values) {
      final threshold = switch (strategy) {
        FranchiseTradeStrategy.contending => 8,
        FranchiseTradeStrategy.middle => 6,
        FranchiseTradeStrategy.rebuilding => 5,
      };
      final rating = switch (strategy) {
        FranchiseTradeStrategy.contending => 90,
        FranchiseTradeStrategy.middle => 70,
        FranchiseTradeStrategy.rebuilding => 40,
      };
      for (final score in [threshold - 1, threshold, threshold + 1]) {
        final adjusted = withOneYearSalaries(career, {
          incomingContract.id: 400,
          outgoingContract.id: 400 + score * 400,
        });
        final controlled = controlledCareer(
          career.copyWith(finances: adjusted),
          aiTeamId: ai.id,
          ratings: {
            for (final team in career.league.teams)
              for (final player in team.players)
                player.id: team.id == ai.id
                    ? rating
                    : strategy == FranchiseTradeStrategy.contending
                    ? 80
                    : strategy == FranchiseTradeStrategy.rebuilding
                    ? 80
                    : team.id == user
                    ? 80
                    : career.league.teams
                          .where((t) => t.id != user && t.id != ai.id)
                          .take(14)
                          .any((t) => t.id == team.id)
                    ? 90
                    : 40,
            incoming.id: rating,
          },
        );
        final proposal = playerOffer(controlled, ai.id, [incoming], opponent);
        final quote = TradeOfferService.evaluate(controlled, proposal);
        expect(quote.valuation!.strategy, strategy);
        expect(quote.valuation!.basketball, 0);
        expect(quote.valuation!.control, 0);
        expect(quote.valuation!.draft, 0);
        expect(quote.valuation!.finance, score);
        expect(quote.valuation!.score, score);
        expect(quote.valuation!.threshold, threshold);
        expect(
          quote.status,
          score > threshold
              ? TradeOfferStatus.legalAccepted
              : TradeOfferStatus.legalRejected,
        );
        expect(
          quote.valuation!.reason,
          score > threshold
              ? TradeEvaluationReason.accepted
              : TradeEvaluationReason.insufficientValue,
        );
      }
    }
  });

  test('top-five pick permits only the rebuilding salary-dump exception', () {
    final ai = career.league.teams.firstWhere(
      (team) => team.id == TeamId('team-2'),
    );
    final star = ai.roster.standardPlayers.firstWhere(
      (player) =>
          ai.roster.standardPlayers
              .where((other) => other.position == player.position)
              .length >=
          3,
    );
    final reserve = ai.roster.standardPlayers.firstWhere(
      (player) => player.id != star.id && player.position == star.position,
    );
    final firstPick = career.draftOrder.pickAt(1);
    final fourthPick = career.draftOrder.pickAt(4);
    final order = DraftOrder(
      picks: [
        for (final pick in career.draftOrder.picks)
          if (pick.overallPick == 1 || pick.overallPick == 4)
            DraftPick(
              round: pick.round,
              pickInRound: pick.pickInRound,
              overallPick: pick.overallPick,
              originalOwnerTeamId: pick.overallPick == 4
                  ? firstPick.originalOwnerTeamId
                  : fourthPick.originalOwnerTeamId,
              currentOwnerTeamId: pick.overallPick == 4
                  ? firstPick.currentOwnerTeamId
                  : fourthPick.currentOwnerTeamId,
            )
          else
            pick,
      ],
    );
    final yearTwo = GmCareer(
      id: career.id,
      generationSeed: career.generationSeed,
      userFranchiseId: user,
      originalSituation: career.originalSituation,
      currentYear: 2,
      league: career.league,
      careerProfiles: career.careerProfiles,
      userOpeningDraftPick: career.userOpeningDraftPick,
      draftOrder: order,
    );
    final starContract = yearTwo.finances.contractForPlayer(star.id)!;
    final reserveIncrease = ai.roster.standardCount <= 14
        ? FinancialRules.minimumSalary
        : 0;
    final adjustedFinances = withOneYearSalaries(yearTwo, {
      starContract.id: 800 + reserveIncrease,
    });
    final pick = yearTwo.draftOrder.pickAt(4);
    expect(pick.overallPick, 4);
    expect(pick.originalOwnerTeamId, user);
    expect(pick.currentOwnerTeamId, user);
    GmCareer fixture(bool contending) => controlledCareer(
      yearTwo.copyWith(finances: adjustedFinances),
      aiTeamId: ai.id,
      ratings: {
        for (final team in career.league.teams)
          for (final player in team.players)
            player.id: team.id == ai.id ? 50 : (contending ? 40 : 80),
        star.id: 82,
        reserve.id: 72,
      },
    );
    PlayerTradeProposal proposalFor(GmCareer state) => PlayerTradeProposal(
      careerId: state.id,
      seasonYear: state.currentYear,
      expectedTradeCount: state.tradeHistory.length,
      firstTeam: user,
      secondTeam: ai.id,
      fromSecond: [(playerId: star.id, contractId: starContract.id)],
      picksFromFirst: [
        (
          draftYear: state.currentYear,
          overallPick: pick.overallPick,
          expectedOwner: user,
        ),
      ],
    );

    final rebuilding = fixture(false);
    final proposal = proposalFor(rebuilding);
    final quote = TradeOfferService.evaluate(rebuilding, proposal);
    expect(
      quote.status,
      TradeOfferStatus.legalAccepted,
      reason: '${quote.legalReason}',
    );
    expect(quote.valuation!.strategy, FranchiseTradeStrategy.rebuilding);
    expect(quote.valuation!.basketball, -84);
    expect(quote.valuation!.control, 0);
    expect(quote.valuation!.draft, 96);
    expect(quote.valuation!.finance, 2);
    expect(quote.valuation!.score, 78);
    expect(quote.valuation!.reason, TradeEvaluationReason.accepted);

    final contender = fixture(true);
    final rejected = TradeOfferService.evaluate(
      contender,
      proposalFor(contender),
    );
    expect(
      rejected.status,
      TradeOfferStatus.legalRejected,
      reason: '${rejected.legalReason}',
    );
    expect(rejected.valuation!.strategy, FranchiseTradeStrategy.contending);
    expect(rejected.valuation!.basketball, -84);
    expect(rejected.valuation!.control, 0);
    expect(rejected.valuation!.draft, 96);
    expect(rejected.valuation!.finance, 2);
    expect(rejected.valuation!.reason, TradeEvaluationReason.eliteReplacement);
  });

  test('superstar for summed weak players fails replacement hard gate', () {
    final ai = career.league.teams.firstWhere(
      (team) => team.id == TeamId('team-2'),
    );
    final userTeam = career.userTeam;
    late Player userAtStarPosition;
    late Player star;
    var found = false;
    for (final opponent in ai.roster.standardPlayers) {
      final aiDepth = ai.roster.standardPlayers
          .where((player) => player.position == opponent.position)
          .length;
      if (aiDepth < 2) continue;
      final incoming = userTeam.roster.standardPlayers
          .where((player) => player.position == opponent.position)
          .firstOrNull;
      if (incoming != null) {
        star = opponent;
        userAtStarPosition = incoming;
        found = true;
        break;
      }
    }
    expect(found, isTrue);
    final aiDepth = {
      for (final p in Position.values)
        p: ai.roster.standardPlayers.where((x) => x.position == p).length,
    };
    final weak = [
      userAtStarPosition,
      ...userTeam.roster.standardPlayers.where(
        (player) =>
            player.id != userAtStarPosition.id &&
            (aiDepth[player.position] ?? 0) >= 2,
      ),
    ].take(3).toList();
    expect(weak, hasLength(3));
    final controlled = controlledCareer(
      career,
      aiTeamId: ai.id,
      ratings: {star.id: 82, weak[0].id: 58, weak[1].id: 61, weak[2].id: 63},
    );
    expect(58 + 61 + 63, greaterThan(82));
    final proposal = playerOffer(
      controlled,
      ai.id,
      [
        for (final player in weak)
          controlled.userTeam.players.firstWhere((p) => p.id == player.id),
      ],
      controlled.league.teams
          .firstWhere((t) => t.id == ai.id)
          .players
          .firstWhere((p) => p.id == star.id),
    );
    final quote = TradeOfferService.evaluate(controlled, proposal);
    expect(quote.status, TradeOfferStatus.legalRejected);
    expect(quote.valuation!.reason, TradeEvaluationReason.eliteReplacement);
  });

  test('older high-guarantee veteran fails without non-financial value', () {
    final ai = career.league.teams.firstWhere(
      (team) => team.id == TeamId('team-2'),
    );
    final userTeam = career.userTeam;
    int guaranteeValue(ContractFinancials schedule) {
      var value = 0;
      for (
        var year = career.currentYear;
        year <= career.currentYear + 4;
        year++
      ) {
        if (year >= schedule.signedYear &&
            year < schedule.signedYear + schedule.guaranteedYears) {
          value += schedule.salaryForYear(year) ?? 0;
        }
      }
      return value;
    }

    Player? veteran;
    Player? cheap;
    for (final candidate in userTeam.roster.standardPlayers) {
      final candidateContract = career.finances.contractForPlayer(
        candidate.id,
      )!;
      final candidateSchedule = career.finances.scheduleFor(
        candidateContract.id,
      )!;
      for (final opponent in ai.roster.standardPlayers) {
        final opponentContract = career.finances.contractForPlayer(
          opponent.id,
        )!;
        final opponentSchedule = career.finances.scheduleFor(
          opponentContract.id,
        )!;
        final aiDepth = ai.roster.standardPlayers
            .where((player) => player.position == opponent.position)
            .length;
        final payrollDelta =
            candidateSchedule.salaryForYear(career.currentYear)! -
            opponentSchedule.salaryForYear(career.currentYear)!;
        final capAfter =
            career.finances.capPayrollFor(ai.id, career.currentYear) +
            payrollDelta;
        if (candidate.position == opponent.position &&
            aiDepth >= 2 &&
            guaranteeValue(candidateSchedule) >
                guaranteeValue(opponentSchedule) &&
            capAfter <= FinancialRules.salaryCap) {
          veteran = candidate;
          cheap = opponent;
          break;
        }
      }
      if (veteran != null) break;
    }
    expect(veteran, isNotNull);
    final veteranPlayer = veteran!;
    final cheapPlayer = cheap!;
    expect(cheap, isNotNull);
    final controlled = controlledCareer(
      career,
      aiTeamId: ai.id,
      ratings: {veteranPlayer.id: 70, cheapPlayer.id: 70},
      ages: {veteranPlayer.id: 35},
    );
    final proposal = playerOffer(
      controlled,
      ai.id,
      [controlled.userTeam.players.firstWhere((p) => p.id == veteranPlayer.id)],
      controlled.league.teams
          .firstWhere((team) => team.id == ai.id)
          .players
          .firstWhere((p) => p.id == cheapPlayer.id),
    );
    final quote = TradeOfferService.evaluate(controlled, proposal);
    expect(quote.status, TradeOfferStatus.legalRejected);
    expect(quote.valuation!.reason, TradeEvaluationReason.guaranteeBurden);
  });

  test('illegal quote has no candidate and cannot be executed', () {
    final picks = career.draftOrder.picks;
    final userPick = picks.firstWhere((p) => p.currentOwnerTeamId == user);
    final otherPick = picks.firstWhere((p) => p.currentOwnerTeamId != user);
    final proposal = pickOffer(
      career,
      career.league.teams.firstWhere(
        (t) => t.id == otherPick.currentOwnerTeamId,
      ),
      [userPick],
      otherPick,
    );
    final stale = PlayerTradeProposal(
      careerId: proposal.careerId,
      seasonYear: proposal.seasonYear,
      expectedTradeCount: 1,
      firstTeam: proposal.firstTeam,
      secondTeam: proposal.secondTeam,
      picksFromFirst: proposal.picksFromFirst,
      picksFromSecond: proposal.picksFromSecond,
    );
    final before = GmCareerCodec.encode(career);
    final quote = TradeOfferService.evaluate(career, stale);
    expect(quote.status, TradeOfferStatus.illegal);
    expect(quote.legalReason, PlayerTradeRejection.staleProposal);
    expect(quote.teamPreviews, isEmpty);
    expect(GmCareerCodec.encode(career), before);
    expect(
      () => TradeOfferService.executeAccepted(career, stale, quote),
      throwsA(isA<TradeQuoteRejected>()),
    );
  });
}

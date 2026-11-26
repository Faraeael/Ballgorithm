import 'package:basketball_manager/features/career/career_controller.dart';
import 'package:basketball_manager/features/career/career_market_tab.dart';
import 'package:basketball_manager/features/career/career_storage.dart';
import 'package:basketball_manager/features/career/career_trade_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simulation_core/simulation_core.dart';

const _user = TeamId('team-1');

int _pickValue(int slot) => switch (slot) {
  <= 5 => 96,
  <= 14 => 64,
  <= 30 => 36,
  <= 45 => 14,
  _ => 5,
};

Future<GmCareerController> _controller() async {
  final controller = GmCareerController(storage: InMemoryGmCareerStorage());
  await controller.startCareer(
    const CareerSetupService().generate(
      const CareerSetupRequest(
        selectedTeamId: _user,
        selectedSituation: FranchiseSituation.tanking,
        seed: 20261028,
      ),
    ),
  );
  addTearDown(controller.dispose);
  return controller;
}

Future<GmCareerController> _controllerFor(GmCareer career) async {
  final controller = GmCareerController(
    storage: InMemoryGmCareerStorage({'default': GmCareerCodec.encode(career)}),
  );
  await controller.loadCareer();
  addTearDown(controller.dispose);
  return controller;
}

(GmCareer, PlayerTradeProposal) _acceptedPlayerFixture(GmCareer career) {
  final ai = career.league.teams.firstWhere(
    (team) => team.id == const TeamId('team-2'),
  );
  for (final outgoing in career.userTeam.roster.standardPlayers) {
    final a = career.finances.contractForPlayer(outgoing.id)!;
    final aSchedule = career.finances.scheduleFor(a.id)!;
    for (final incoming in ai.roster.standardPlayers) {
      final b = career.finances.contractForPlayer(incoming.id)!;
      final bSchedule = career.finances.scheduleFor(b.id)!;
      if (outgoing.position != incoming.position ||
          ai.roster.standardPlayers
                  .where((p) => p.position == incoming.position)
                  .length <
              2 ||
          a.startYear != b.startYear ||
          a.durationYears != b.durationYears ||
          aSchedule.signedYear != bSchedule.signedYear ||
          aSchedule.guaranteedYears != bSchedule.guaranteedYears ||
          aSchedule.annualSalaries.join(',') !=
              bSchedule.annualSalaries.join(',')) {
        continue;
      }
      final ratings = <PlayerId, int>{};
      final teams = [
        for (final team in career.league.teams)
          team.copyWith(
            roster: Roster([
              for (final player in team.players)
                () {
                  final rating = player.id == outgoing.id
                      ? 72
                      : player.id == incoming.id
                      ? 70
                      : team.id == _user
                      ? 60
                      : team.id == ai.id
                      ? 55
                      : int.parse(team.id.value.substring(5)) <= 10
                      ? 80
                      : 40;
                  ratings[player.id] = rating;
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
                }(),
            ], categories: team.roster.categories),
          ),
      ];
      final profiles = {
        for (final entry in career.careerProfiles.profiles.entries)
          entry.key: PlayerCareerProfile(
            playerId: entry.value.playerId,
            age: 28,
            potential:
                (ratings[entry.value.playerId] ?? entry.value.potential) >
                    entry.value.potential
                ? ratings[entry.value.playerId]!
                : entry.value.potential,
            trajectory: entry.value.trajectory,
          ),
      };
      final controlled = career.copyWith(
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
      return (controlled, _playerOffer(controlled, ai, outgoing, incoming));
    }
  }
  throw StateError('No equal-salary player fixture');
}

(GmCareer, PlayerTradeProposal) _cashReserveFixture(GmCareer career) {
  final finances = career.finances;
  final team = finances.financesFor(_user);
  final cash = finances.projectedEndOfSeasonCash(_user, career.currentYear);
  final reserve =
      FinancialRules.minimumSalary *
      (FinancialRules.minimumStandardRoster -
          career.userTeam.roster.standardCount);
  final adjusted = career.copyWith(
    finances: CareerFinances(
      contracts: finances.contracts.values,
      schedules: finances.schedules.values,
      teamFinances: [
        for (final old in finances.teamFinances.values)
          if (old.teamId == _user)
            TeamFinances(
              teamId: _user,
              operatingBudget: team.operatingBudget,
              cash: team.cash,
              revenueBaseline: team.revenueBaseline - cash + reserve,
              season: career.currentYear,
              capGrandfathered: team.capGrandfathered,
              grandfatheredPayroll: team.grandfatheredPayroll,
              capException: team.capException,
            )
          else
            old,
      ],
      staffCommitments: finances.staffCommitments.values,
      facilities: finances.facilities.values,
      guaranteedLiabilities: finances.guaranteedLiabilities.values,
      debtByTeam: finances.debtByTeam,
    ),
  );
  int salary(Player p) => finances
      .scheduleFor(finances.contractForPlayer(p.id)!.id)!
      .salaryForYear(career.currentYear)!;
  final ai = career.league.teams.firstWhere(
    (t) => t.id == const TeamId('team-2'),
  );
  final cheap = career.userTeam.players.reduce(
    (a, b) => salary(a) < salary(b) ? a : b,
  );
  final costly = ai.players.reduce((a, b) => salary(a) > salary(b) ? a : b);
  return (adjusted, _playerOffer(adjusted, ai, cheap, costly));
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _composeAcceptedPickOffer(
  WidgetTester tester,
  GmCareer career,
) async {
  final offered = career.draftOrder.picksForTeam(_user);
  final requested =
      career.draftOrder.picks
          .where((pick) => pick.currentOwnerTeamId != _user)
          .toList()
        ..sort(
          (a, b) =>
              _pickValue(a.overallPick).compareTo(_pickValue(b.overallPick)),
        );
  final pick = requested.first;
  final partner = career.league.teams.firstWhere(
    (team) => team.id == pick.currentOwnerTeamId,
  );
  await _tapVisible(tester, find.byType(DropdownButtonFormField<TeamId>));
  await tester.scrollUntilVisible(
    find.text(partner.name),
    200,
    scrollable: find.byType(Scrollable).last,
  );
  await _tapVisible(tester, find.text(partner.name).last);
  for (final item in offered) {
    await _tapVisible(
      tester,
      find.byKey(
        ValueKey('trade-asset-pick:${career.currentYear}:${item.overallPick}'),
      ),
    );
  }
  await _tapVisible(
    tester,
    find.byKey(
      ValueKey('trade-asset-pick:${career.currentYear}:${pick.overallPick}'),
    ),
  );
  await _tapVisible(tester, find.byKey(const ValueKey('trade-preview')));
}

PlayerTradeProposal _playerOffer(
  GmCareer career,
  Team partner,
  Player outgoing,
  Player incoming, {
  bool mixed = false,
}) => PlayerTradeProposal(
  careerId: career.id,
  seasonYear: career.currentYear,
  expectedTradeCount: career.tradeHistory.length,
  firstTeam: _user,
  secondTeam: partner.id,
  fromFirst: [
    (
      playerId: outgoing.id,
      contractId: career.finances.contractForPlayer(outgoing.id)!.id,
    ),
  ],
  fromSecond: [
    (
      playerId: incoming.id,
      contractId: career.finances.contractForPlayer(incoming.id)!.id,
    ),
  ],
  picksFromFirst: mixed
      ? [
          for (final pick in career.draftOrder.picksForTeam(_user))
            (
              draftYear: career.currentYear,
              overallPick: pick.overallPick,
              expectedOwner: _user,
            ),
        ]
      : const [],
);

PlayerTradeProposal _findPlayerOffer(
  GmCareer career,
  TradeOfferStatus status, {
  bool mixed = false,
  Set<String>? outgoingIds,
}) {
  for (final partner in career.league.teams.where((team) => team.id != _user)) {
    for (final outgoing in career.userTeam.roster.standardPlayers) {
      if (outgoingIds != null && !outgoingIds.contains(outgoing.id.value)) {
        continue;
      }
      for (final incoming in partner.roster.standardPlayers) {
        final offer = _playerOffer(
          career,
          partner,
          outgoing,
          incoming,
          mixed: mixed,
        );
        final quote = TradeOfferService.evaluate(career, offer);
        if (quote.status == status &&
            (status != TradeOfferStatus.illegal ||
                quote.legalReason == PlayerTradeRejection.capPayroll ||
                quote.legalReason == PlayerTradeRejection.futureCapPayroll ||
                quote.legalReason == PlayerTradeRejection.cashReserve)) {
          return offer;
        }
      }
    }
  }
  throw StateError('No matching player trade fixture: $status, mixed=$mixed');
}

Future<void> _composePlayerOffer(
  WidgetTester tester,
  GmCareer career,
  PlayerTradeProposal offer,
) async {
  final partner = career.league.teams.firstWhere(
    (team) => team.id == offer.secondTeam,
  );
  await _tapVisible(tester, find.byType(DropdownButtonFormField<TeamId>));
  await tester.scrollUntilVisible(
    find.text(partner.name),
    200,
    scrollable: find.byType(Scrollable).last,
  );
  await _tapVisible(tester, find.text(partner.name).last);
  Future<void> select(Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await _tapVisible(tester, finder);
  }

  for (final player in offer.fromFirst) {
    await select(
      find.byKey(ValueKey('trade-asset-player:${player.playerId.value}')),
    );
  }
  for (final pick in offer.picksFromFirst) {
    await select(
      find.byKey(
        ValueKey('trade-asset-pick:${pick.draftYear}:${pick.overallPick}'),
      ),
    );
  }
  for (final player in offer.fromSecond) {
    await select(
      find.byKey(ValueKey('trade-asset-player:${player.playerId.value}')),
    );
  }
  await select(find.byKey(const ValueKey('trade-preview')));
  await tester.scrollUntilVisible(
    find.byKey(const ValueKey('trade-quote-status')),
    300,
    scrollable: find.byType(Scrollable).first,
  );
}

Future<void> _confirmPlayerOffer(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.byKey(const ValueKey('trade-confirm')),
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await _tapVisible(tester, find.byKey(const ValueKey('trade-confirm')));
  await _tapVisible(tester, find.widgetWithText(FilledButton, 'Confirm trade'));
}

void _expectFinancePreview(TradeOfferQuote quote) {
  for (final preview in quote.teamPreviews.values) {
    expect(
      find.text(
        'Cap payroll: ${preview.capPayrollBefore} → ${preview.capPayrollAfter} CU',
      ),
      findsWidgets,
    );
    expect(
      find.text(
        'Cash payroll (including guarantees): ${preview.cashPayrollBefore} → ${preview.cashPayrollAfter} CU',
      ),
      findsWidgets,
    );
    expect(
      find.text(
        'Projected cash after debt: ${preview.projectedCashAfterDebtBefore} → ${preview.projectedCashAfterDebtAfter} CU',
      ),
      findsWidgets,
    );
    expect(
      find.text(
        'Minimum roster reserve: ${preview.minimumRosterReserveBefore} → ${preview.minimumRosterReserveAfter} CU',
      ),
      findsWidgets,
    );
  }
}

void main() {
  testWidgets('market opens trade center on a narrow screen', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = await _controller();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CareerMarketTab(controller: controller)),
      ),
    );
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('market-open-trade-center')),
    );
    expect(find.byType(CareerTradeScreen), findsOneWidget);
    expect(find.text('No completed trades yet.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('quote invalidates after career reload', (tester) async {
    final controller = await _controller();
    await tester.pumpWidget(
      MaterialApp(home: CareerTradeScreen(controller: controller)),
    );
    await tester.pumpAndSettle();
    await _composeAcceptedPickOffer(tester, controller.career!);
    expect(find.textContaining('Legal trade, accepted'), findsOneWidget);
    expect(controller.career!.tradeHistory, isEmpty);
    await controller.loadCareer();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('trade-stale')),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const ValueKey('trade-stale')), findsOneWidget);
    expect(find.byKey(const ValueKey('trade-confirm')), findsNothing);
  });

  testWidgets('confirmation shows quote and saved receipt', (tester) async {
    final controller = await _controller();
    await tester.pumpWidget(
      MaterialApp(home: CareerTradeScreen(controller: controller)),
    );
    await tester.pumpAndSettle();
    await _composeAcceptedPickOffer(tester, controller.career!);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('trade-confirm')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await _tapVisible(tester, find.byKey(const ValueKey('trade-confirm')));
    final dialog = find.byType(AlertDialog);
    expect(
      find.descendant(of: dialog, matching: find.textContaining('YOU SEND')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialog, matching: find.textContaining('YOU RECEIVE')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: dialog,
        matching: find.textContaining('Cap payroll:'),
      ),
      findsNWidgets(2),
    );
    expect(
      find.descendant(
        of: dialog,
        matching: find.textContaining('Projected cash after debt:'),
      ),
      findsNWidgets(2),
    );
    expect(controller.career!.tradeHistory, isEmpty);
    await _tapVisible(
      tester,
      find.widgetWithText(FilledButton, 'Confirm trade'),
    );
    expect(controller.career!.tradeHistory, hasLength(1));
    await tester.scrollUntilVisible(
      find.textContaining('recorded payroll impact'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining(controller.career!.tradeHistory.single.id),
      findsOneWidget,
    );
  });

  for (final mixed in [false, true]) {
    testWidgets(
      'accepted ${mixed ? 'mixed' : 'player'} trade transfers and reloads',
      (tester) async {
        final original = await _controller();
        final (fixture, playerOffer) = _acceptedPlayerFixture(original.career!);
        final controller = mixed ? original : await _controllerFor(fixture);
        final before = controller.career!;
        final offer = mixed
            ? _findPlayerOffer(
                before,
                TradeOfferStatus.legalAccepted,
                mixed: true,
              )
            : playerOffer;
        final quote = controller.evaluateTrade(offer);
        await tester.pumpWidget(
          MaterialApp(home: CareerTradeScreen(controller: controller)),
        );
        await tester.pumpAndSettle();
        await _composePlayerOffer(tester, before, offer);
        expect(find.textContaining('Legal trade, accepted'), findsOneWidget);
        _expectFinancePreview(quote);
        expect(
          GmCareerCodec.encode(controller.career!),
          GmCareerCodec.encode(before),
        );
        await _confirmPlayerOffer(tester);

        final after = controller.career!;
        expect(after.tradeHistory, hasLength(1));
        for (final move in [
          (asset: offer.fromFirst.single, from: _user, to: offer.secondTeam),
          (asset: offer.fromSecond.single, from: offer.secondTeam, to: _user),
        ]) {
          final oldContract = before.finances.contractForPlayer(
            move.asset.playerId,
          )!;
          final contract = after.finances.contractForPlayer(
            move.asset.playerId,
          )!;
          final oldSchedule = before.finances.scheduleFor(oldContract.id)!;
          final schedule = after.finances.scheduleFor(contract.id)!;
          expect(contract.id, oldContract.id);
          expect(contract.teamId, move.to);
          expect(contract.category, oldContract.category);
          expect(contract.startYear, oldContract.startYear);
          expect(contract.durationYears, oldContract.durationYears);
          expect(contract.source, oldContract.source);
          expect(schedule.teamId, move.to);
          expect(schedule.annualSalaries, oldSchedule.annualSalaries);
          expect(schedule.guaranteedYears, oldSchedule.guaranteedYears);
          expect(schedule.source, oldSchedule.source);
          expect(schedule.signedYear, oldSchedule.signedYear);
          final sender = after.league.teams.firstWhere(
            (team) => team.id == move.from,
          );
          final recipient = after.league.teams.firstWhere(
            (team) => team.id == move.to,
          );
          expect(
            sender.players.any((player) => player.id == move.asset.playerId),
            isFalse,
          );
          expect(
            recipient.players.any((player) => player.id == move.asset.playerId),
            isTrue,
          );
        }
        for (final pick in offer.picksFromFirst) {
          expect(
            after.draftOrder.picks
                .singleWhere((p) => p.overallPick == pick.overallPick)
                .currentOwnerTeamId,
            offer.secondTeam,
          );
        }
        for (final entry in quote.teamPreviews.entries) {
          expect(
            after.finances.capPayrollFor(entry.key, after.currentYear),
            entry.value.capPayrollAfter,
          );
          expect(
            after.finances.cashPayrollFor(entry.key, after.currentYear),
            entry.value.cashPayrollAfter,
          );
        }
        final saved = GmCareerCodec.encode(after);
        await controller.loadCareer();
        await tester.pumpAndSettle();
        expect(GmCareerCodec.encode(controller.career!), saved);
        await tester.scrollUntilVisible(
          find.textContaining(after.tradeHistory.single.id),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        expect(
          find.textContaining(after.tradeHistory.single.id),
          findsOneWidget,
        );
      },
    );
  }

  for (final status in [
    TradeOfferStatus.legalRejected,
    TradeOfferStatus.illegal,
  ]) {
    testWidgets('player offer shows $status without writing', (tester) async {
      final original = await _controller();
      final (fixture, illegalOffer) = _cashReserveFixture(original.career!);
      final controller = status == TradeOfferStatus.illegal
          ? await _controllerFor(fixture)
          : original;
      final career = controller.career!;
      final offer = status == TradeOfferStatus.illegal
          ? illegalOffer
          : _findPlayerOffer(career, status);
      final quote = controller.evaluateTrade(offer);
      final saved = GmCareerCodec.encode(career);
      await tester.pumpWidget(
        MaterialApp(home: CareerTradeScreen(controller: controller)),
      );
      await tester.pumpAndSettle();
      await _composePlayerOffer(tester, career, offer);
      expect(
        find.textContaining(
          status == TradeOfferStatus.illegal
              ? 'Illegal trade:'
              : 'Legal trade, rejected:',
        ),
        findsOneWidget,
      );
      if (status == TradeOfferStatus.illegal) {
        final reason = switch (quote.legalReason) {
          PlayerTradeRejection.capPayroll =>
            'Current cap payroll rules would be violated.',
          PlayerTradeRejection.futureCapPayroll =>
            'Future scheduled cap payroll would be violated.',
          PlayerTradeRejection.cashReserve =>
            'Projected cash cannot cover the minimum roster reserve.',
          _ => throw StateError('Expected a financial rejection'),
        };
        expect(find.textContaining(reason), findsOneWidget);
      }
      if (status == TradeOfferStatus.legalRejected) {
        _expectFinancePreview(quote);
      }
      expect(find.byKey(const ValueKey('trade-confirm')), findsNothing);
      expect(GmCareerCodec.encode(controller.career!), saved);
      await controller.loadCareer();
      expect(GmCareerCodec.encode(controller.career!), saved);
    });
  }

  testWidgets(
    'player selection invalidates quote and retained manual plan needs repair',
    (tester) async {
      final original = await _controller();
      final (fixture, offer) = _acceptedPlayerFixture(original.career!);
      final controller = await _controllerFor(fixture);
      final initial = controller.career!;
      final team = RegularSeasonGameAdapter.standardTeamFor(initial.userTeam);
      final lineup = CourtLineup.defaultFor(team);
      final outgoingId = offer.fromFirst.single.playerId.value;
      final starters = lineup.playerIds.contains(outgoingId)
          ? lineup.playerIds
          : [outgoingId, ...lineup.playerIds.skip(1)];
      final manual = CareerRotationSettings.manual(
        starters: [for (final id in starters) PlayerId(id)],
        preset: RotationPreset.starterHeavy,
      );
      await controller.updateUserRotation(manual);
      await controller.delegateUserRotationKeepingManual();
      final before = controller.career!;
      expect(
        controller.evaluateTrade(offer).status,
        TradeOfferStatus.legalAccepted,
      );
      await tester.pumpWidget(
        MaterialApp(home: CareerTradeScreen(controller: controller)),
      );
      await tester.pumpAndSettle();
      await _composePlayerOffer(tester, before, offer);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('trade-confirm')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const ValueKey('trade-confirm')), findsOneWidget);
      final outgoing = find.byKey(
        ValueKey('trade-asset-player:${offer.fromFirst.single.playerId.value}'),
      );
      await tester.scrollUntilVisible(
        outgoing,
        -300,
        scrollable: find.byType(Scrollable).first,
      );
      await _tapVisible(tester, outgoing);
      expect(find.byKey(const ValueKey('trade-confirm')), findsNothing);
      expect(find.byKey(const ValueKey('trade-quote-status')), findsNothing);
      await _tapVisible(tester, outgoing);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('trade-preview')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await _tapVisible(tester, find.byKey(const ValueKey('trade-preview')));
      await _confirmPlayerOffer(tester);
      expect(controller.career!.userRotation.retainedManual, manual);
      await controller.loadCareer();
      await tester.pumpAndSettle();
      expect(controller.career!.userRotation.retainedManual, manual);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('trade-rotation-repair')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('trade-rotation-repair')),
      );
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('rotation-restore-manual')),
      );
      expect(
        find.textContaining('saved manual plan no longer fits the roster'),
        findsOneWidget,
      );
      expect(controller.career!.userRotation.retainedManual, manual);
      await _tapVisible(tester, find.byKey(const ValueKey('rotation-save')));
      expect(controller.career!.userRotation.isManual, isTrue);
      expect(
        controller.career!.userRotation.starters,
        isNot(contains(offer.fromFirst.single.playerId)),
      );
    },
  );
}

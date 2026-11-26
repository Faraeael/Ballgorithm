import 'package:simulation_core/simulation_core.dart';
import 'package:test/test.dart';

EmergencyTeamReceipt _receipt({
  String teamId = 'team-4',
  int standardBefore = 13,
  int payrollBefore = 41800,
  int cashBefore = 10000,
  int ordinaryRelief = 800,
  int hardshipRelief = 0,
  bool grandfathered = false,
  int grandfatheredPayroll = 0,
  List<Position> missing = const [],
}) => EmergencyTeamReceipt(
  teamId: TeamId(teamId),
  standardBefore: standardBefore,
  payrollBefore: payrollBefore,
  cashBefore: cashBefore,
  ordinaryRelief: ordinaryRelief,
  hardshipRelief: hardshipRelief,
  grandfathered: grandfathered,
  grandfatheredPayroll: grandfatheredPayroll,
  missingPositionsBefore: missing,
  priorContractIds: [
    for (var i = 10; i < 10 + standardBefore; i++) 'contract-$i',
  ],
);

EmergencyOffer _offer(
  int salary,
  int relief, {
  String teamId = 'team-4',
  String playerId = 'player-7',
}) => EmergencyOffer(
  teamId: TeamId(teamId),
  playerId: PlayerId(playerId),
  seasonYear: 1,
  salary: salary,
  relief: relief,
);

EmergencySettlement _settlement(
  List<EmergencyOffer> offers,
  List<EmergencyTeamReceipt> teams,
) => EmergencySettlement(
  seasonYear: 1,
  humanApproved: false,
  searchStatus: EmergencyPlanStatus.optimal,
  offers: offers,
  teams: teams,
);

void main() {
  test('emergency preview does not start before settlement', () {
    final career = GmCareer.fromSetupResult(
      const CareerSetupService().generate(
        const CareerSetupRequest(
          selectedTeamId: TeamId('team-1'),
          selectedSituation: FranchiseSituation.tanking,
          seed: 1604126146,
        ),
      ),
      id: 'emergency-prerequisites',
    );
    final plan = const EmergencyRosterService().preview(career);
    expect(plan.status, EmergencyPlanStatus.inconclusive);
    expect(plan.offers, isEmpty);
    expect(plan.blockers, contains('Rookie decisions are incomplete'));
    expect(
      plan.blockers,
      contains('Both free-agent market rounds must be complete'),
    );
    expect(
      plan.blockers,
      contains('Clearance and hardship settlement must be complete'),
    );
    expect(plan.exploredStates, 0);
  });

  test('offer identity binds franchise, player, season and salary', () {
    final offer = _offer(1170, 1170);
    expect(offer.offerId, 'emergency-offer-team-4-player-7-1-1170');
    expect(
      offer.transactionId,
      FreeAgentAcquisition.idFor(offer.playerId, offer.seasonYear),
    );
  });

  test('settlement binds exact incremental relief and round-trips', () {
    final original = _settlement([_offer(1170, 1170)], [_receipt()]);
    final decoded = EmergencySettlement.fromJson(original.toJson());
    expect(decoded.toJson(), original.toJson());
    expect(decoded.teams.single.priorContractIds, hasLength(13));
    expect(
      () => _settlement([_offer(1170, 1169)], [_receipt()]),
      throwsFormatException,
    );
    expect(
      () => _settlement([_offer(1170, 1171)], [_receipt()]),
      throwsFormatException,
    );
  });

  test('incremental authority cannot be reused across offers', () {
    EmergencySettlement make(int secondRelief) => _settlement(
      [
        _offer(400, 0, teamId: 'team-1', playerId: 'player-1'),
        _offer(400, secondRelief, teamId: 'team-1', playerId: 'player-2'),
      ],
      [
        _receipt(
          teamId: 'team-1',
          standardBefore: 12,
          payrollBefore: 40500,
          cashBefore: 800,
          ordinaryRelief: 0,
        ),
      ],
    );
    expect(make(300).offers.map((offer) => offer.relief), [0, 300]);
    expect(() => make(400), throwsFormatException);
    expect(() => make(0), throwsFormatException);
  });

  test('starting payroll must already be lawful under recorded authority', () {
    expect(
      () => _settlement([_offer(1170, 1170)], [_receipt(ordinaryRelief: 700)]),
      throwsFormatException,
    );
    expect(
      _settlement(
        [_offer(1170, 1170)],
        [_receipt(ordinaryRelief: 700, hardshipRelief: 100)],
      ).teams.single.startingLimit,
      41800,
    );
    expect(
      () => _settlement(
        [_offer(1170, 1170)],
        [_receipt(ordinaryRelief: 700, hardshipRelief: 301)],
      ),
      throwsFormatException,
    );
    expect(
      () => _settlement(
        [_offer(1170, 1170)],
        [_receipt(grandfathered: true, hardshipRelief: 100)],
      ),
      throwsFormatException,
    );
  });

  test('emergency cannot expand a roster without a mandatory shortage', () {
    expect(
      () => _settlement([_offer(1170, 1170)], [_receipt(standardBefore: 14)]),
      throwsFormatException,
    );
    expect(
      () => _settlement(
        [
          _offer(600, 600, playerId: 'player-1'),
          _offer(600, 600, playerId: 'player-2'),
        ],
        [_receipt()],
      ),
      throwsFormatException,
    );
    final positionOnly = _settlement(
      [_offer(1170, 1170)],
      [
        _receipt(standardBefore: 14, missing: const [Position.c]),
      ],
    );
    expect(positionOnly.teams.single.missingPositionsBefore, [Position.c]);
    expect(
      () => _settlement(
        [_offer(1170, 1170)],
        [
          _receipt(
            standardBefore: 14,
            missing: const [Position.pg, Position.c],
          ),
        ],
      ),
      returnsNormally,
    );
    expect(
      () => _settlement(
        [_offer(1170, 1170)],
        [
          _receipt(standardBefore: 14, missing: const [Position.c, Position.c]),
        ],
      ),
      throwsFormatException,
    );
  });

  test('execution rejects an invented plan before any mutation', () {
    final career = GmCareer.fromSetupResult(
      const CareerSetupService().generate(
        const CareerSetupRequest(
          selectedTeamId: TeamId('team-1'),
          selectedSituation: FranchiseSituation.tanking,
          seed: 1604126146,
        ),
      ),
      id: 'emergency-forged-plan',
    );
    final before = GmCareerCodec.encode(career);
    final forged = EmergencyRosterPlan(
      status: EmergencyPlanStatus.optimal,
      offers: [_offer(400, 0, teamId: 'team-1')],
      teams: const [],
      exploredStates: 0,
      blockers: const [],
    );
    expect(
      () => const EmergencyRosterService().execute(
        career,
        forged,
        humanApproved: true,
      ),
      throwsStateError,
    );
    expect(GmCareerCodec.encode(career), before);
  });

  test('receipt JSON rejects tampering, reordering and unknown fields', () {
    final original = _settlement(
      [_offer(1200, 1200)],
      [_receipt(cashBefore: 1200)],
    );
    Map<String, dynamic> copy() =>
        EmergencySettlement.fromJson(original.toJson()).toJson()
            as Map<String, dynamic>;
    expect(EmergencySettlement.fromJson(copy()).toJson(), original.toJson());

    final transaction = copy();
    ((transaction['offers'] as List).single
            as Map<String, Object?>)['transactionId'] =
        'other-transaction';
    final sequence = copy();
    ((sequence['offers'] as List).single as Map<String, Object?>)['sequence'] =
        1;
    final extraTeamKey = copy();
    ((extraTeamKey['teams'] as List).single
            as Map<String, Object?>)['spareRoom'] =
        500;
    final position = copy();
    ((position['teams'] as List).single
        as Map<String, Object?>)['missingPositionsBefore'] = [
      'XX',
    ];
    final contracts = copy();
    ((contracts['teams'] as List).single
        as Map<String, Object?>)['priorContractIds'] = [
      'contract-9',
    ];
    for (final json in [
      transaction,
      sequence,
      extraTeamKey,
      position,
      contracts,
    ]) {
      expect(() => EmergencySettlement.fromJson(json), throwsFormatException);
    }
    expect(
      () => _settlement([_offer(1201, 1201)], original.teams),
      throwsFormatException,
    );
    expect(
      () => _settlement([
        original.offers.single,
        original.offers.single,
      ], original.teams),
      throwsFormatException,
    );
    expect(
      () => _settlement([_offer(1200, 1200)], [_receipt(cashBefore: 1199)]),
      throwsFormatException,
    );
  });
}

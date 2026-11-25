import 'dart:convert';

import 'package:simulation_core/simulation_core.dart';
import 'package:simulation_core/src/domain_versions.dart' as domain_versions;
import 'package:test/test.dart';

const _adapter = RegularSeasonGameAdapter();

/// Real draft, signing, free agency and clearance; offseason cleared.
GmCareer _clearedOffseason({String teamId = 'team-1'}) {
  const seed = 20261028;
  final setup = const CareerSetupService().generate(
    CareerSetupRequest(
      selectedTeamId: TeamId(teamId),
      selectedSituation: FranchiseSituation.tanking,
      seed: seed,
    ),
  );
  var c = GmCareer.fromSetupResult(setup, id: 'm010-$teamId-$seed');
  const draft = DraftExecutionService();
  const aiSigning = RookieAiSigningService();
  const signing = RookieSigningService();
  const market = FreeAgentMarketService();
  const clearance = OffseasonClearanceService();
  const hardship = HardshipSettlementService();
  c = draft.startDraft(c);
  while (!c.draftExecutionState.isCompleted) {
    if (c.draftExecutionState.isHumanTurn(
      order: c.draftOrder,
      userTeamId: c.userFranchiseId,
    )) {
      final pick = c.draftClass.prospects.firstWhere(
        (p) => !c.draftExecutionState.draftRights.containsKey(p.id.value),
      );
      c = draft.makeHumanSelection(career: c, prospectId: pick.id);
    } else {
      c = draft.executeAiSelection(c);
    }
  }
  c = aiSigning.initialize(c);
  while (aiSigning.pendingRights(c).isNotEmpty) {
    c = aiSigning.applyNextDecision(c);
  }
  for (final r in c.unsignedDraftRights) {
    if (r.owningTeamId == c.userFranchiseId) {
      c = signing.signDraftedRookie(
        career: c,
        teamId: c.userFranchiseId,
        prospectId: r.prospectId,
        category: RosterCategory.standard,
        durationYears: 2,
      );
    }
  }
  for (var round = 0; round < 2; round++) {
    c = market.startRound(c);
    c = market.prepareResolution(c);
    while (c.freeAgentMarket.isResolvable) {
      c = market.resolveNext(c);
    }
  }
  c = clearance.start(c);
  c = clearance.prepare(c);
  while (c.offseasonClearance.isResolvable) {
    c = clearance.resolveNext(c);
  }
  c = hardship.prepare(c, humanParticipationConfirmed: true);
  while (c.hardshipSettlement.isResolvable) {
    c = hardship.resolveNext(c);
  }
  return clearance.markCleared(c);
}

GmCareer _scheduled(GmCareer cleared) => const RegularSeasonScheduleService()
    .generate(const RegularSeasonEntryService().start(cleared));

/// Fabricated (home 104–96) regular season whose inputs still come from the
/// production adapter, so stored evidence matches the career's settings.
GmCareer _fabricateRegularSeason(GmCareer c) {
  final simLeague = _adapter.simulationLeagueFor(c);
  final rs0 = c.regularSeasonState!;
  final schedule = rs0.schedule!;
  final teamById = {for (final t in simLeague.teams) t.id: t};
  String? leagueJson;
  String? snapshotId;
  final results = <String, RegularSeasonGameResult>{};
  final rounds = <RegularSeasonRound>[];
  for (final round in schedule.rounds) {
    final fixtures = <RegularSeasonFixture>[];
    for (final f in round.fixtures) {
      final input = _adapter.createInput(c, f, simulationLeague: simLeague);
      final captured = RegularSeasonGameInputEvidence.capture(input);
      leagueJson ??= captured.leagueSnapshotJson;
      snapshotId ??= captured.evidence.leagueSnapshotId;
      final lines = <SeasonPlayerGameLine>[];
      void addLines(Team team, int total) {
        final players = team.players.take(8).toList();
        for (var i = 0; i < players.length; i++) {
          final pts = total ~/ players.length + (i < total % 8 ? 1 : 0);
          lines.add(
            SeasonPlayerGameLine(
              playerId: players[i].id.value,
              teamId: team.id.value,
              secondsPlayed: 1440,
              points: pts,
              fgm: pts ~/ 2,
              fga: pts ~/ 2 + 4,
              threePm: 0,
              threePa: 2,
              ftm: pts % 2,
              fta: pts % 2,
              oreb: 1,
              dreb: 3,
              rebounds: 4,
              assists: 2,
              steals: 1,
              blocks: 0,
              turnovers: 1,
              personalFouls: 2,
            ),
          );
        }
      }

      addLines(teamById[f.homeTeamId]!, 104);
      addLines(teamById[f.awayTeamId]!, 96);
      results[f.id] = RegularSeasonGameResult(
        fixtureId: f.id,
        seasonId: rs0.seasonId,
        seasonYear: rs0.seasonYear,
        homeTeamId: f.homeTeamId,
        awayTeamId: f.awayTeamId,
        gameSeed: f.gameSeed,
        inputFingerprint: GameFingerprint.of(input),
        simulationVersion: gameSimulationVersion,
        rulesVersion: gameRulesVersion,
        eventSchemaVersion: gameEventSchemaVersion,
        prngImplementationId: 'xorshift32-v1',
        fingerprintVersion: gameFingerprintVersion,
        coreEngineVersion: domain_versions.coreEngineVersion,
        leagueSchemaVersion: domain_versions.snapshotSchemaVersion,
        inputEvidence: captured.evidence,
        periodsPlayed: 4,
        summary: SeasonGameSummary(
          homeScore: 104,
          awayScore: 96,
          winnerTeamId: f.homeTeamId,
          periodScoresHome: const {'Q1': 26, 'Q2': 26, 'Q3': 26, 'Q4': 26},
          periodScoresAway: const {'Q1': 24, 'Q2': 24, 'Q3': 24, 'Q4': 24},
          playerLines: {for (final l in lines) l.playerId: l},
        ),
      );
      fixtures.add(
        RegularSeasonFixture(
          id: f.id,
          seasonId: f.seasonId,
          seasonYear: f.seasonYear,
          roundNumber: f.roundNumber,
          fixturePosition: f.fixturePosition,
          homeTeamId: f.homeTeamId,
          awayTeamId: f.awayTeamId,
          gameSeed: f.gameSeed,
          status: RegularSeasonFixtureStatus.completed,
        ),
      );
    }
    rounds.add(
      RegularSeasonRound(roundNumber: round.roundNumber, fixtures: fixtures),
    );
  }
  return c.copyWith(
    regularSeasonState: rs0.copyWith(
      gameResults: results,
      gameInputSnapshots: {snapshotId!: leagueJson!},
      schedule: RegularSeasonSchedule(
        seasonId: schedule.seasonId,
        seasonYear: schedule.seasonYear,
        scheduleSeed: schedule.scheduleSeed,
        rounds: rounds,
      ),
    ),
  );
}

/// The exact pre-M010 adapter construction, kept as an independent reference.
GameInput _baselineInput(GmCareer c, RegularSeasonFixture f) {
  final teams = [
    for (final source in c.league.teams)
      source.copyWith(
        roster: Roster(
          source.roster.players
              .where(
                (p) =>
                    source.roster.categoryOf(p.id) == RosterCategory.standard,
              )
              .toList(),
        ),
      ),
  ];
  final league = League.create(
    id: c.league.id,
    name: c.league.name,
    config: c.league.config,
    teams: teams,
    enforceRosterSize: false,
  );
  final home = teams.firstWhere((t) => t.id == f.homeTeamId);
  final away = teams.firstWhere((t) => t.id == f.awayTeamId);
  final rules = GameRules.standard;
  TeamRotationPlan balanced(Team team, CourtLineup lineup) =>
      TeamRotationPlan.create(
        team: team,
        preset: RotationPreset.balanced,
        targets: [
          for (final e in RotationPlan.expandPreset(
            preset: RotationPreset.balanced,
            team: team,
            lineup: lineup,
            rules: rules,
          ).entries)
            RotationTarget(playerId: e.key, seconds: e.value),
        ],
      );
  final hl = CourtLineup.defaultFor(home);
  final al = CourtLineup.defaultFor(away);
  return GameInput.create(
    gameId: f.id,
    league: league,
    homeTeamId: f.homeTeamId,
    awayTeamId: f.awayTeamId,
    homeLineup: hl,
    awayLineup: al,
    seed: f.gameSeed,
    rules: rules,
    rotationPlan: RotationPlan(
      home: balanced(home, hl),
      away: balanced(away, al),
    ),
  );
}

Team _userStandardTeam(GmCareer c) =>
    RegularSeasonGameAdapter.standardTeamFor(c.userTeam);

/// Default starters with the PG slot taken by the first bench player.
List<PlayerId> _manualStarters(GmCareer c) {
  final team = _userStandardTeam(c);
  final lineup = CourtLineup.defaultFor(team);
  final starters = [for (final id in lineup.playerIds) PlayerId(id)];
  final bench = team.players.firstWhere(
    (p) => !lineup.playerIds.contains(p.id.value),
  );
  return [bench.id, ...starters.skip(1)];
}

/// Starters 2,880 s each, every other standard player an explicit 0.
CareerRotationSettings _starterOnlyCustom(GmCareer c) {
  final starters = _manualStarters(c);
  final ids = {for (final id in starters) id.value};
  return CareerRotationSettings.manual(
    starters: starters,
    preset: RotationPreset.custom,
    customTargets: {
      for (final p in _userStandardTeam(c).players)
        p.id.value: ids.contains(p.id.value) ? 2880 : 0,
    },
  );
}

Map<String, Object?> _payload(GameInput input) =>
    jsonDecode(jsonEncode(GameFingerprint.canonicalPayload(input)))
        as Map<String, Object?>;

void main() {
  late GmCareer cleared;
  late GmCareer scheduled;

  setUpAll(() {
    cleared = _clearedOffseason();
    scheduled = _scheduled(cleared);
  });

  group('M010-T02 CareerRotationSettings persistence', () {
    test('AUTO and manual settings round-trip through the current schema', () {
      expect(GmCareerCodec.currentSchemaVersion, 27);
      expect(scheduled.userRotation, CareerRotationSettings.auto);
      final autoJson = jsonDecode(GmCareerCodec.encode(scheduled)) as Map;
      expect(autoJson['schemaVersion'], GmCareerCodec.currentSchemaVersion);
      expect(autoJson['userRotation'], {'mode': 'auto'});

      for (final settings in [
        CareerRotationSettings.manual(
          starters: _manualStarters(scheduled),
          preset: RotationPreset.starterHeavy,
        ),
        _starterOnlyCustom(scheduled),
      ]) {
        final manual = scheduled.copyWith(userRotation: settings);
        final decoded = GmCareerCodec.decode(GmCareerCodec.encode(manual));
        expect(decoded.userRotation, settings);
        expect(GmCareerCodec.encode(decoded), GmCareerCodec.encode(manual));
      }
    });

    test(
      'v25 saves migrate to AUTO; misplaced or missing keys are rejected',
      () {
        final map =
            jsonDecode(GmCareerCodec.encode(scheduled)) as Map<String, dynamic>;
        final v25 = Map<String, dynamic>.of(map)
          ..['schemaVersion'] = 25
          ..remove('userRotation')
          ..remove('staff');
        final migrated = GmCareerCodec.decode(jsonEncode(v25));
        expect(migrated.userRotation, CareerRotationSettings.auto);
        expect(migrated.schemaVersion, GmCareerCodec.currentSchemaVersion);

        // userRotation itself is rejected below v26 (staff removed so the
        // failure can only come from userRotation).
        final v25WithKey = Map<String, dynamic>.of(map)
          ..['schemaVersion'] = 25
          ..remove('staff');
        expect(
          () => GmCareerCodec.decode(jsonEncode(v25WithKey)),
          throwsFormatException,
        );
        final v26Missing = Map<String, dynamic>.of(map)
          ..['schemaVersion'] = 26
          ..remove('userRotation')
          ..remove('staff');
        expect(
          () => GmCareerCodec.decode(jsonEncode(v26Missing)),
          throwsFormatException,
        );
      },
    );

    test('malformed settings are rejected with FormatException', () {
      final s = ['a', 'b', 'c', 'd', 'e'];
      final malformed = <Object?>[
        null,
        'auto',
        {'mode': 'coach'},
        {'mode': 'auto', 'starters': s},
        {
          'mode': 'manual',
          'starters': s.take(4).toList(),
          'preset': 'balanced',
        },
        {
          'mode': 'manual',
          'starters': [...s.take(4), 'a'],
          'preset': 'balanced',
        },
        {
          'mode': 'manual',
          'starters': [1, 2, 3, 4, 5],
          'preset': 'balanced',
        },
        {'mode': 'manual', 'starters': s, 'preset': 'heavy'},
        {'mode': 'manual', 'starters': s, 'preset': 'custom'},
        {
          'mode': 'manual',
          'starters': s,
          'preset': 'balanced',
          'customTargets': {'a': 10},
        },
        {
          'mode': 'manual',
          'starters': s,
          'preset': 'custom',
          'customTargets': {'a': -1},
        },
        {
          'mode': 'manual',
          'starters': s,
          'preset': 'custom',
          'customTargets': {'a': 2881},
        },
        {
          'mode': 'manual',
          'starters': s,
          'preset': 'custom',
          'customTargets': {'a': 1.5},
        },
        {'mode': 'manual', 'starters': s, 'preset': 'balanced', 'extra': 1},
      ];
      for (final raw in malformed) {
        expect(
          () => CareerRotationSettings.fromJson(raw),
          throwsFormatException,
          reason: '$raw',
        );
      }
      // Structurally valid but obsolete (unknown players): kept, not rejected.
      final obsolete = CareerRotationSettings.fromJson({
        'mode': 'manual',
        'starters': s,
        'preset': 'balanced',
      });
      expect(obsolete.starters.map((id) => id.value), s);
    });
  });

  group('M010-T02 simulator integration', () {
    test('AUTO reproduces the pre-M010 game inputs exactly', () {
      final schedule = scheduled.regularSeasonState!.schedule!;
      var compared = 0;
      for (final round in schedule.rounds.take(3)) {
        for (final f in round.fixtures) {
          expect(
            GameFingerprint.of(_adapter.createInput(scheduled, f)),
            GameFingerprint.of(_baselineInput(scheduled, f)),
            reason: f.id,
          );
          compared++;
        }
      }
      expect(compared, 45);
    });

    test(
      'MANUAL drives the human side (home and away); AI sides unchanged',
      () {
        final settings = CareerRotationSettings.manual(
          starters: _manualStarters(scheduled),
          preset: RotationPreset.starterHeavy,
        );
        final manual = scheduled.copyWith(userRotation: settings);
        final user = scheduled.userFranchiseId;
        final fixtures = scheduled.regularSeasonState!.schedule!.allFixtures;
        final homeGame = fixtures.firstWhere((f) => f.homeTeamId == user);
        final awayGame = fixtures.firstWhere((f) => f.awayTeamId == user);
        for (final (fixture, side) in [
          (homeGame, 'home'),
          (awayGame, 'away'),
        ]) {
          final other = side == 'home' ? 'away' : 'home';
          final auto = _payload(_adapter.createInput(scheduled, fixture));
          final man = _payload(_adapter.createInput(manual, fixture));
          final lineup = (man['${side}Lineup'] as List)
              .map((slot) => (slot as Map)['playerId'])
              .toList();
          expect(lineup, settings.starters.map((id) => id.value).toList());
          final plan = (man['rotationPlan'] as Map)[side] as Map;
          expect(plan['preset'], 'starterHeavy');
          expect(man['${side}Lineup'], isNot(auto['${side}Lineup']));
          // Opponent (AI) lineup and plan are byte-identical to AUTO.
          expect(man['${other}Lineup'], auto['${other}Lineup']);
          expect(
            (man['rotationPlan'] as Map)[other],
            (auto['rotationPlan'] as Map)[other],
          );
          expect(man['league'], auto['league']);
          expect(man['gameSeed'], auto['gameSeed']);
        }
      },
    );

    test(
      'MANUAL changes actual participation; single-round is deterministic',
      () {
        final user = scheduled.userFranchiseId;
        final round1 = scheduled.regularSeasonState!.schedule!.rounds.first;
        final userGame = round1.fixtures.firstWhere(
          (f) => f.homeTeamId == user || f.awayTeamId == user,
        );
        const rounds = RegularSeasonRoundService();
        final settings = _starterOnlyCustom(scheduled);
        final manual = scheduled.copyWith(userRotation: settings);
        final autoResult = rounds
            .simulateNextRound(scheduled, expectedRoundNumber: 1)
            .regularSeasonState!
            .gameResults[userGame.id]!;
        final manualRun = rounds.simulateNextRound(
          manual,
          expectedRoundNumber: 1,
        );
        final manualResult =
            manualRun.regularSeasonState!.gameResults[userGame.id]!;
        final rerun = rounds.simulateNextRound(manual, expectedRoundNumber: 1);
        expect(
          GmCareerCodec.encode(rerun),
          GmCareerCodec.encode(manualRun),
          reason: 'deterministic manual round',
        );

        final starterIds = {for (final id in settings.starters) id.value};
        int seconds(RegularSeasonGameResult r, bool starters) => [
          for (final line in r.summary.playerLines.values)
            if (line.teamId == user.value &&
                starterIds.contains(line.playerId) == starters)
              line.secondsPlayed,
        ].fold(0, (a, b) => a + b);
        final autoBench = seconds(autoResult, false);
        final manualBench = seconds(manualResult, false);
        final manualStarters = seconds(manualResult, true);
        // ignore: avoid_print
        print(
          'M010 participation: AUTO bench=${autoBench}s, '
          'MANUAL bench=${manualBench}s, MANUAL starters=${manualStarters}s',
        );
        expect(
          manualResult.inputFingerprint,
          isNot(autoResult.inputFingerprint),
        );
        expect(manualStarters, greaterThan(autoBench));
        expect(manualBench, lessThan(autoBench));
        // AI games in the same round are unaffected by the human plan.
        for (final f in round1.fixtures) {
          if (f.id == userGame.id) continue;
          expect(
            manualRun.regularSeasonState!.gameResults[f.id]!.inputFingerprint,
            GameFingerprint.of(_baselineInput(scheduled, f)),
          );
        }
      },
    );

    test(
      'Play-In and playoffs use the saved plan; history immutable; rollover carries it',
      () {
        final settings = CareerRotationSettings.manual(
          starters: _manualStarters(scheduled),
          preset: RotationPreset.starterHeavy,
        );
        var c = _fabricateRegularSeason(
          scheduled.copyWith(userRotation: settings),
        );
        c = const PlayInEntryService().enter(c);
        final user = c.userFranchiseId.value;
        const playIn = PlayInGameService();
        for (var g = 1; g <= 3; g++) {
          c = playIn.simulateGame(
            c,
            expectedGameId: '${c.regularSeasonState!.seasonId}-playin-g$g',
          );
        }
        c = const PlayoffEntryService().enter(c);
        const slates = PlayoffSlateService();
        c = slates.simulateNextSlate(c);

        final starterIds = settings.starters.map((id) => id.value).toList();
        var checked = 0;
        void checkUserGames(Iterable<RegularSeasonGameResult> results) {
          for (final r in results) {
            final side = r.homeTeamId.value == user
                ? 'home'
                : r.awayTeamId.value == user
                ? 'away'
                : null;
            if (side == null) continue;
            final template =
                jsonDecode(r.inputEvidence!.payloadTemplateJson) as Map;
            expect(
              (template['${side}Lineup'] as List)
                  .map((s) => (s as Map)['playerId'])
                  .toList(),
              starterIds,
            );
            expect(
              ((template['rotationPlan'] as Map)[side] as Map)['preset'],
              'starterHeavy',
            );
            checked++;
          }
        }

        checkUserGames(c.playInState!.gameResults.values);
        checkUserGames(c.playoffState!.gameResults.values);
        // ignore: avoid_print
        print('M010 postseason user games checked: $checked');
        expect(
          c.playoffState!.qualifiedTeams.map((t) => t.teamId.value),
          contains(user),
        );
        expect(checked, greaterThan(0));

        // Historical integrity: switching to AUTO mid-postseason keeps every
        // stored result and fingerprint, and validation uses stored inputs.
        final before = jsonEncode(c.regularSeasonState!.toJson());
        final switched = c.copyWith(userRotation: CareerRotationSettings.auto);
        final reloaded = GmCareerCodec.decode(GmCareerCodec.encode(switched));
        expect(jsonEncode(reloaded.regularSeasonState!.toJson()), before);
        expect(
          jsonEncode(reloaded.playoffState!.toJson()),
          jsonEncode(c.playoffState!.toJson()),
        );

        while (!c.playoffState!.isComplete) {
          c = slates.simulateNextSlate(c);
        }
        final archiveManual = SeasonArchiveCodec.encodeWithDigest(
          SeasonArchive.fromCareer(c),
        ).digest;
        final archiveAuto = SeasonArchiveCodec.encodeWithDigest(
          SeasonArchive.fromCareer(
            c.copyWith(userRotation: CareerRotationSettings.auto),
          ),
        ).digest;
        expect(archiveAuto, archiveManual);

        final next = const SeasonRolloverService()
            .prepareArchiveAndRollover(current: c)
            .rolloverResult
            .nextCareer;
        expect(next.currentYear, 2);
        expect(next.userRotation, settings);
      },
      timeout: const Timeout(Duration(minutes: 10)),
    );

    test(
      'Play-In: a human play-in team simulates with its saved plan',
      () {
        // Fabricated standings ignore rosters, so seeds do not depend on which
        // franchise is human; pick the seed-15 franchise as the human team.
        final probe = const PlayInEntryService().enter(
          _fabricateRegularSeason(scheduled),
        );
        final seed15 = probe.playInState!.originalRanking[14];
        var c = _scheduled(_clearedOffseason(teamId: seed15.value));
        final settings = CareerRotationSettings.manual(
          starters: _manualStarters(c),
          preset: RotationPreset.starterHeavy,
        );
        c = _fabricateRegularSeason(c.copyWith(userRotation: settings));
        c = const PlayInEntryService().enter(c);
        expect(c.playInState!.originalRanking[14], c.userFranchiseId);
        c = const PlayInGameService().simulateGame(
          c,
          expectedGameId: '${c.regularSeasonState!.seasonId}-playin-g1',
        );
        final result = c.playInState!.gameResults.values.single;
        final side = result.homeTeamId == c.userFranchiseId ? 'home' : 'away';
        expect({
          result.homeTeamId,
          result.awayTeamId,
        }, contains(c.userFranchiseId));
        final template =
            jsonDecode(result.inputEvidence!.payloadTemplateJson) as Map;
        expect(
          (template['${side}Lineup'] as List)
              .map((s) => (s as Map)['playerId'])
              .toList(),
          settings.starters.map((id) => id.value).toList(),
        );
        expect(
          ((template['rotationPlan'] as Map)[side] as Map)['preset'],
          'starterHeavy',
        );
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );
  });

  group('M010-T02 roster reconciliation', () {
    test(
      'departure, two-way reclassification and acquisition are reported, not erased',
      () {
        final team = _userStandardTeam(scheduled);
        final settings = _starterOnlyCustom(scheduled);
        expect(CareerRotationService.resolve(settings, team).isValid, isTrue);
        final departed = settings.starters[2];

        // Departure / retirement: player gone from the standard roster.
        final without = team.copyWith(
          roster: Roster(team.players.where((p) => p.id != departed).toList()),
        );
        final r1 = CareerRotationService.resolve(settings, without);
        expect(r1.isValid, isFalse);
        expect(
          r1.issues.map((i) => i.code),
          containsAll([
            CareerRotationIssueCode.starterUnavailable,
            CareerRotationIssueCode.targetPlayerUnavailable,
          ]),
        );
        expect(r1.issues.first.slot, Position.values[2]);

        // Two-way reclassification is excluded by standardTeamFor.
        final reclassified = RegularSeasonGameAdapter.standardTeamFor(
          team.copyWith(
            roster: Roster(
              team.players,
              categories: {
                for (final p in team.players)
                  p.id.value: p.id == departed
                      ? RosterCategory.twoWay
                      : RosterCategory.standard,
              },
            ),
          ),
        );
        expect(
          CareerRotationService.resolve(
            settings,
            reclassified,
          ).issues.first.code,
          CareerRotationIssueCode.starterUnavailable,
        );

        // Acquisition: new player is unassigned (0 s), plan stays valid.
        final newcomer = Player(
          id: const PlayerId('m010-newcomer'),
          firstName: 'New',
          lastName: 'Comer',
          position: Position.c,
          attributes: team.players.last.attributes,
        );
        final grown = team.copyWith(
          roster: Roster([...team.players, newcomer]),
        );
        final r3 = CareerRotationService.resolve(settings, grown);
        expect(r3.isValid, isTrue);
        expect(r3.unassignedPlayerIds, [newcomer.id]);
        expect(r3.plan!.secondsFor(newcomer.id), 0);
        // An explicit zero is not "unassigned".
        expect(
          CareerRotationService.resolve(settings, team).unassignedPlayerIds,
          isEmpty,
        );
      },
    );

    test(
      'repair proposal is deterministic and never redistributes custom seconds',
      () {
        final team = _userStandardTeam(scheduled);
        final departed = _manualStarters(scheduled)[2];
        final without = team.copyWith(
          roster: Roster(team.players.where((p) => p.id != departed).toList()),
        );

        // Preset plan: starter replaced (slot position first), fully repaired.
        final preset = CareerRotationSettings.manual(
          starters: _manualStarters(scheduled),
          preset: RotationPreset.balanced,
        );
        final p1 = CareerRotationService.proposeRepair(preset, without)!;
        final p2 = CareerRotationService.proposeRepair(preset, without)!;
        expect(p1.settings, p2.settings);
        expect(p1.isApplicable, isTrue);
        final replacement = without.players.firstWhere(
          (p) => p.id == p1.settings.starters[2],
        );
        final starterSet = {for (final id in preset.starters) id.value};
        final sameSlotBench = without.players
            .where((p) => !starterSet.contains(p.id.value))
            .where((p) => p.position == Position.values[2]);
        if (sameSlotBench.isNotEmpty) {
          expect(replacement.id, sameSlotBench.first.id);
        }
        expect(preset.starters[2], departed, reason: 'original preserved');

        // Custom plan: departed seconds dropped, shortfall remains an issue.
        final custom = _starterOnlyCustom(scheduled);
        final p3 = CareerRotationService.proposeRepair(custom, without)!;
        expect(p3.isApplicable, isFalse);
        expect(p3.settings.customTargets.containsKey(departed.value), isFalse);
        expect(
          p3.remainingIssues.map((i) => i.validationCode),
          anyOf(
            contains(GameValidationCode.invalidRotationTotal),
            contains(GameValidationCode.starterTargetNotPositive),
          ),
        );
        final kept = p3.settings.customTargets.values.fold(0, (a, b) => a + b);
        expect(kept, 2880 * 4, reason: 'no redistribution of custom seconds');

        // Valid plans have nothing to repair; AUTO is never repaired.
        expect(CareerRotationService.proposeRepair(custom, team), isNull);
        expect(
          CareerRotationService.proposeRepair(
            CareerRotationSettings.auto,
            team,
          ),
          isNull,
        );
      },
    );

    test(
      'obsolete manual plan is kept offseason, blocks entry and simulation',
      () {
        const ghost = PlayerId('ghost-player');
        final starters = _manualStarters(scheduled);
        final obsolete = CareerRotationSettings.manual(
          starters: [ghost, ...starters.skip(1)],
          preset: RotationPreset.balanced,
        );
        // Offseason careers may hold obsolete plans (preserved, round-trips).
        final offseason = cleared.copyWith(userRotation: obsolete);
        final reloaded = GmCareerCodec.decode(GmCareerCodec.encode(offseason));
        expect(reloaded.userRotation, obsolete);
        final issues = CareerRotationService.resolveForCareer(reloaded).issues;
        expect(issues.single.code, CareerRotationIssueCode.starterUnavailable);
        expect(issues.single.playerId, ghost);

        // D2: season entry is blocked; the stored plan is untouched.
        expect(
          () => const RegularSeasonEntryService().start(offseason),
          throwsA(isA<CareerRotationInvalidException>()),
        );
        expect(offseason.userRotation, obsolete);
        // Switching to AUTO is an explicit way through the gate.
        expect(
          const RegularSeasonEntryService()
              .start(
                offseason.copyWith(userRotation: CareerRotationSettings.auto),
              )
              .phase,
          CareerPhase.regularSeason,
        );

        // In-season careers cannot hold an unresolvable manual plan.
        expect(
          () => scheduled.copyWith(userRotation: obsolete),
          throwsFormatException,
        );
        // The adapter never falls back to AUTO.
        final game = scheduled.regularSeasonState!.schedule!.allFixtures
            .firstWhere(
              (f) =>
                  f.homeTeamId == scheduled.userFranchiseId ||
                  f.awayTeamId == scheduled.userFranchiseId,
            );
        expect(
          () => _adapter.createGameInput(
            offseason,
            gameId: game.id,
            homeTeamId: game.homeTeamId,
            awayTeamId: game.awayTeamId,
            seed: game.gameSeed,
          ),
          throwsA(isA<CareerRotationInvalidException>()),
        );
      },
    );
  });
}

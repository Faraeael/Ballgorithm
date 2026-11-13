import 'dart:convert';

import 'package:simulation_core/simulation_core.dart';
import 'package:test/test.dart';

const _seed = 20261028;
const _team = TeamId('team-1');

void main() {
  late GmCareer career;

  setUpAll(() {
    career = _career(FranchiseSituation.playIn);
  });

  group('M008-T08A free agent pool', () {
    test('1-2. exactly 90 deterministic free agents', () {
      final pool = career.freeAgentPool;
      expect(pool.length, 90);
      expect(FreeAgentPool.expectedSize, 90);

      final same = _career(FranchiseSituation.playIn);
      expect(
        jsonEncode(same.freeAgentPool.toJson()),
        jsonEncode(pool.toJson()),
      );

      final different = _career(FranchiseSituation.playIn, seed: 20261029);
      expect(
        jsonEncode(different.freeAgentPool.toJson()),
        isNot(jsonEncode(pool.toJson())),
      );
    });

    test('2b. all four human situations share the same free-agent pool', () {
      final baseline = jsonEncode(
        _career(FranchiseSituation.tanking).freeAgentPool.toJson(),
      );
      for (final situation in FranchiseSituation.values) {
        expect(
          jsonEncode(_career(situation).freeAgentPool.toJson()),
          baseline,
          reason: situation.name,
        );
      }
    });

    test('3-5. identities are unique and never collide', () {
      final pool = career.freeAgentPool;
      final ids = pool.entries.map((entry) => entry.id.value).toList();
      expect(ids.toSet().length, 90);
      expect(ids.first, 'free-agent-1');
      expect(ids.last, 'free-agent-90');

      final rosterIds = {
        for (final team in career.league.teams)
          for (final player in team.players) player.id.value,
      };
      final prospectIds = {
        for (final prospect in career.draftClass.prospects) prospect.id.value,
      };
      for (final id in ids) {
        expect(rosterIds, isNot(contains(id)));
        expect(prospectIds, isNot(contains(id)));
      }
    });

    test('6. all five positions have at least 12 free agents', () {
      final counts = <Position, int>{};
      for (final entry in career.freeAgentPool.entries) {
        counts[entry.player.position] =
            (counts[entry.player.position] ?? 0) + 1;
      }
      expect(counts.keys.length, 5);
      for (final position in Position.values) {
        expect(counts[position], greaterThanOrEqualTo(12));
      }
      expect(counts.values.fold<int>(0, (a, b) => a + b), 90);
    });

    test('7-9. attributes, profiles, ages and potentials are valid', () {
      for (final entry in career.freeAgentPool.entries) {
        final attributes = entry.player.attributes;
        for (final value in attributes.asMap.values) {
          expect(value, inInclusiveRange(0, 100));
        }
        expect(
          PlayerAttributes.fromJson(attributes.toJson()).overallRating,
          attributes.overallRating,
        );
        expect(entry.profile.playerId, entry.player.id);
        expect(entry.profile.age, inInclusiveRange(20, 36));
        expect(
          entry.profile.potential,
          inInclusiveRange(attributes.overallRating, 100),
        );
        entry.profile.validate(entry.player);
      }
    });

    test('10. free agents have no franchise, contract or draft ownership', () {
      final ids = career.freeAgentPool.playerIds;
      for (final team in career.league.teams) {
        for (final player in team.players) {
          expect(ids, isNot(contains(player.id.value)));
        }
      }
      for (final id in ids) {
        final playerId = PlayerId(id);
        expect(career.rookieSigningLedger.isSigned(playerId), isFalse);
        expect(career.draftExecutionState.draftRights.containsKey(id), isFalse);
        expect(career.aiRookieSigning.hasDecision(playerId), isFalse);
        expect(career.careerProfiles.forPlayer(playerId), isNull);
      }
    });

    test('11-13. league, draft and signings are independent of the pool', () {
      final alternative = const FreeAgentGenerator().generate(seed: 777001);
      final swapped = career.copyWith(freeAgentPool: alternative);
      expect(
        jsonEncode(swapped.league.toJson()),
        jsonEncode(career.league.toJson()),
      );
      expect(
        jsonEncode(swapped.draftOrder.toJson()),
        jsonEncode(career.draftOrder.toJson()),
      );
      expect(
        jsonEncode(swapped.draftClass.toJson()),
        jsonEncode(career.draftClass.toJson()),
      );
      expect(
        jsonEncode(swapped.draftExecutionState.toJson()),
        jsonEncode(career.draftExecutionState.toJson()),
      );
      expect(
        jsonEncode(swapped.rookieSigningLedger.toJson()),
        jsonEncode(career.rookieSigningLedger.toJson()),
      );
      expect(
        jsonEncode(swapped.aiRookieSigning.toJson()),
        jsonEncode(career.aiRookieSigning.toJson()),
      );
    });

    test('14. save/load preserves the pool byte-for-byte', () {
      final encoded = GmCareerCodec.encode(career);
      final decoded = GmCareerCodec.decode(encoded);
      expect(
        jsonEncode(decoded.freeAgentPool.toJson()),
        jsonEncode(career.freeAgentPool.toJson()),
      );
      expect(GmCareerCodec.encode(decoded), encoded);
      expect(decoded.schemaVersion, GmCareerCodec.currentSchemaVersion);
    });

    test('15. v6 saves migrate with a deterministic generated pool', () {
      final encoded =
          jsonDecode(GmCareerCodec.encode(career)) as Map<String, dynamic>;
      final v6 = Map<String, dynamic>.from(encoded)
        ..['schemaVersion'] = 6
        ..remove('freeAgentPool');
      final migrated = GmCareerCodec.decode(jsonEncode(v6));

      final expected = const FreeAgentGenerator().generate(seed: _seed);
      expect(
        jsonEncode(migrated.freeAgentPool.toJson()),
        jsonEncode(expected.toJson()),
      );
      expect(
        jsonEncode(migrated.league.toJson()),
        jsonEncode(career.league.toJson()),
      );
      expect(
        jsonEncode(migrated.draftClass.toJson()),
        jsonEncode(career.draftClass.toJson()),
      );
      expect(
        jsonEncode(migrated.rookieSigningLedger.toJson()),
        jsonEncode(career.rookieSigningLedger.toJson()),
      );
      expect(
        jsonEncode(migrated.aiRookieSigning.toJson()),
        jsonEncode(career.aiRookieSigning.toJson()),
      );
      final reencoded =
          jsonDecode(GmCareerCodec.encode(migrated)) as Map<String, dynamic>;
      expect(reencoded['schemaVersion'], GmCareerCodec.currentSchemaVersion);
      expect(reencoded['freeAgentPool'], isNotNull);
    });

    test('15b. v1 saves migrate and still generate the same pool', () {
      final encoded =
          jsonDecode(GmCareerCodec.encode(career)) as Map<String, dynamic>;
      final v1 = Map<String, dynamic>.from(encoded)
        ..['schemaVersion'] = 1
        ..remove('freeAgentPool')
        ..remove('aiRookieSigning')
        ..remove('rookieSigningLedger')
        ..remove('draftExecutionState')
        ..remove('rosterMemberships')
        ..remove('draftOrder')
        ..remove('draftClass');
      final migrated = GmCareerCodec.decode(jsonEncode(v1));
      expect(migrated.freeAgentPool.length, 90);
      expect(
        jsonEncode(migrated.freeAgentPool.toJson()),
        jsonEncode(career.freeAgentPool.toJson()),
      );
      expect(migrated.draftClass.length, 90);
      expect(migrated.draftOrder.totalPicks, 60);
    });

    test('16. a persisted pool is never regenerated on load', () {
      final encoded =
          jsonDecode(GmCareerCodec.encode(career)) as Map<String, dynamic>;
      final pool = encoded['freeAgentPool'] as Map<String, dynamic>;
      final entries = List<dynamic>.from(
        pool['entries'] as List,
      ).reversed.toList();
      pool['entries'] = entries;
      final decoded = GmCareerCodec.decode(jsonEncode(encoded));
      expect(decoded.freeAgentPool.entries.first.id.value, 'free-agent-90');
      expect(decoded.freeAgentPool.entries.last.id.value, 'free-agent-1');
    });

    test('17. corrupted v7 pool data is rejected', () {
      FormatException failure(Map<String, dynamic> json) {
        try {
          GmCareerCodec.decode(jsonEncode(json));
        } on FormatException catch (error) {
          return error;
        }
        fail('Expected FormatException');
      }

      Map<String, dynamic> base() =>
          jsonDecode(GmCareerCodec.encode(career)) as Map<String, dynamic>;
      List<dynamic> entries(Map<String, dynamic> json) =>
          (json['freeAgentPool'] as Map<String, dynamic>)['entries'] as List;

      final missing = base()..remove('freeAgentPool');
      expect(
        failure(missing).message,
        contains('Missing or invalid freeAgentPool'),
      );

      final duplicate = base();
      final dupEntries = entries(duplicate);
      final first = dupEntries.first as Map<String, dynamic>;
      final second = dupEntries[1] as Map<String, dynamic>;
      final firstPlayer = first['player'] as Map<String, dynamic>;
      final secondPlayer = second['player'] as Map<String, dynamic>;
      secondPlayer['id'] = firstPlayer['id'];
      (second['profile'] as Map<String, dynamic>)['playerId'] =
          firstPlayer['id'];
      expect(failure(duplicate).message, contains('Duplicate free-agent ID'));

      final collision = base();
      final collisionPlayer =
          (entries(collision).first as Map<String, dynamic>)['player']
              as Map<String, dynamic>;
      final rosterPlayer = career.league.teams.first.players.first;
      collisionPlayer['id'] = rosterPlayer.id.value;
      ((entries(collision).first as Map<String, dynamic>)['profile']
              as Map<String, dynamic>)['playerId'] =
          rosterPlayer.id.value;
      expect(failure(collision).message, contains('initial identity snapshot'));

      final badAge = base();
      ((entries(badAge).first as Map<String, dynamic>)['profile']
              as Map<String, dynamic>)['age'] =
          19;
      expect(failure(badAge).message, contains('outside 20..36'));

      final badPotential = base();
      ((entries(badPotential).first as Map<String, dynamic>)['profile']
              as Map<String, dynamic>)['potential'] =
          0;
      expect(failure(badPotential), isA<FormatException>());

      final positionShortage = base();
      final positionEntries = entries(positionShortage);
      final pgCount = positionEntries
          .where(
            (entry) =>
                ((entry as Map<String, dynamic>)['player']
                    as Map<String, dynamic>)['position'] ==
                'PG',
          )
          .length;
      expect(pgCount, greaterThanOrEqualTo(12));
      var moved = 0;
      for (final entry in positionEntries) {
        final player =
            (entry as Map<String, dynamic>)['player'] as Map<String, dynamic>;
        if (player['position'] == 'PG' && moved < pgCount - 11) {
          player['position'] = 'SG';
          moved++;
        }
      }
      expect(
        GmCareerCodec.decode(jsonEncode(positionShortage)).freeAgentPool.length,
        90,
      );

      final profileCollision = base();
      final profiles =
          ((profileCollision['careerProfiles']
                  as Map<String, dynamic>)['profiles']
              as Map<String, dynamic>);
      profiles['free-agent-1'] = {
        'playerId': 'free-agent-1',
        'age': 25,
        'potential': 70,
        'trajectory': 'steady',
      };
      expect(
        failure(profileCollision).message,
        contains('roster career profile'),
      );
    });

    test('18. public evaluation omits hidden potential and trajectory', () {
      final entry = career.freeAgentPool.entries.first;
      final view = entry.toPublicView();
      final json = view.toJson();
      expect(json['id'], entry.id.value);
      expect(json['position'], entry.player.position.shortName);
      expect(json['age'], entry.profile.age);
      expect(json['overallRating'], entry.player.attributes.overallRating);
      expect(json.containsKey('potential'), isFalse);
      expect(json.containsKey('trajectory'), isFalse);
      expect(jsonEncode(json), isNot(contains('trajectory')));
    });

    test('19. league readiness reporting is unchanged by the pool', () {
      var completed = _completeDraft(career);
      completed = const RookieAiSigningService().advanceAll(completed);
      final baseline = LeagueReadinessReport.fromCareer(completed);
      final swapped = completed.copyWith(
        freeAgentPool: const FreeAgentGenerator().generate(seed: 909090),
      );
      final after = LeagueReadinessReport.fromCareer(swapped);

      expect(after.readyCount, baseline.readyCount);
      expect(after.notReadyCount, baseline.notReadyCount);
      expect(after.totalStandardShortage, baseline.totalStandardShortage);
      expect(after.aiStandardSignings, baseline.aiStandardSignings);
      expect(after.aiTwoWaySignings, baseline.aiTwoWaySignings);
      expect(after.aiDeferredRights, baseline.aiDeferredRights);
      expect(after.pendingAiDecisions, baseline.pendingAiDecisions);
      expect(after.userTeam.standardCount, baseline.userTeam.standardCount);
    });

    test('20. generated population statistics', () {
      final pool = career.freeAgentPool;
      final positions = <Position, int>{};
      final ageBands = <String, int>{'20-23': 0, '24-29': 0, '30-36': 0};
      final overallTiers = <String, int>{
        '<60': 0,
        '60-64': 0,
        '65-69': 0,
        '70-74': 0,
        '75-79': 0,
        '80+': 0,
      };
      var potentialSum = 0;
      var overallSum = 0;
      for (final entry in pool.entries) {
        positions[entry.player.position] =
            (positions[entry.player.position] ?? 0) + 1;
        final age = entry.profile.age;
        if (age <= 23) {
          ageBands['20-23'] = ageBands['20-23']! + 1;
        } else if (age <= 29) {
          ageBands['24-29'] = ageBands['24-29']! + 1;
        } else {
          ageBands['30-36'] = ageBands['30-36']! + 1;
        }
        final overall = entry.player.attributes.overallRating;
        overallSum += overall;
        potentialSum += entry.profile.potential;
        final tier = overall < 60
            ? '<60'
            : overall < 65
            ? '60-64'
            : overall < 70
            ? '65-69'
            : overall < 75
            ? '70-74'
            : overall < 80
            ? '75-79'
            : '80+';
        overallTiers[tier] = overallTiers[tier]! + 1;
      }
      // ignore: avoid_print
      print(
        'T08A pool: positions=$positions ages=$ageBands '
        'overall=$overallTiers avgOverall=${(overallSum / 90).toStringAsFixed(1)} '
        'avgPotential=${(potentialSum / 90).toStringAsFixed(1)}',
      );
      expect(pool.length, 90);
      expect(overallTiers.values.fold<int>(0, (a, b) => a + b), 90);
      expect(overallTiers['80+']! <= 10, isTrue);
      expect(overallTiers['<60']!, greaterThan(0));
    });
  });
}

GmCareer _career(
  FranchiseSituation situation, {
  int seed = _seed,
  TeamId teamId = _team,
}) {
  final setup = const CareerSetupService().generate(
    CareerSetupRequest(
      selectedTeamId: teamId,
      selectedSituation: situation,
      seed: seed,
    ),
  );
  return GmCareer.fromSetupResult(setup, id: 't08a-${situation.name}-$seed');
}

GmCareer _completeDraft(GmCareer career) {
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

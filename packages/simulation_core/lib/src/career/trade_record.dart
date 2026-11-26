import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/contract_financials.dart';
import '../models/ids.dart';
import '../models/player_contract.dart';
import 'career_phase.dart';

enum TradeAssetKind { player, pick, rights }

/// Canonical history for one moved asset. Current ownership remains elsewhere.
final class TradeAssetTransfer {
  const TradeAssetTransfer._({
    required this.kind,
    required this.from,
    required this.to,
    this.playerId,
    this.contractId,
    this.startYear,
    this.endYear,
    this.termsDigest,
    this.draftYear,
    this.overallPick,
    this.originalOwner,
  });

  const TradeAssetTransfer.player({
    required PlayerId playerId,
    required String contractId,
    required TeamId from,
    required TeamId to,
    required int startYear,
    required int endYear,
    required String termsDigest,
  }) : this._(
         kind: TradeAssetKind.player,
         playerId: playerId,
         contractId: contractId,
         from: from,
         to: to,
         startYear: startYear,
         endYear: endYear,
         termsDigest: termsDigest,
       );

  const TradeAssetTransfer.pick({
    required int draftYear,
    required int overallPick,
    required TeamId originalOwner,
    required TeamId from,
    required TeamId to,
  }) : this._(
         kind: TradeAssetKind.pick,
         draftYear: draftYear,
         overallPick: overallPick,
         originalOwner: originalOwner,
         from: from,
         to: to,
       );

  const TradeAssetTransfer.rights({
    required PlayerId prospectId,
    required int draftYear,
    required int overallPick,
    required TeamId originalOwner,
    required TeamId from,
    required TeamId to,
  }) : this._(
         kind: TradeAssetKind.rights,
         playerId: prospectId,
         draftYear: draftYear,
         overallPick: overallPick,
         originalOwner: originalOwner,
         from: from,
         to: to,
       );

  final TradeAssetKind kind;
  final TeamId from;
  final TeamId to;
  final PlayerId? playerId;
  final String? contractId;
  final int? startYear;
  final int? endYear;
  final String? termsDigest;
  final int? draftYear;
  final int? overallPick;
  final TeamId? originalOwner;

  String get canonicalKey => switch (kind) {
    TradeAssetKind.player => 'player:${playerId!.value}',
    TradeAssetKind.pick => 'pick:$draftYear:$overallPick',
    TradeAssetKind.rights => 'rights:$draftYear:${playerId!.value}',
  };

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'from': from.value,
    'to': to.value,
    if (kind == TradeAssetKind.player) ...{
      'playerId': playerId!.value,
      'contractId': contractId,
      'startYear': startYear,
      'endYear': endYear,
      'termsDigest': termsDigest,
    },
    if (kind != TradeAssetKind.player) ...{
      if (kind == TradeAssetKind.rights) 'playerId': playerId!.value,
      'draftYear': draftYear,
      'overallPick': overallPick,
      'originalOwner': originalOwner!.value,
    },
  };

  factory TradeAssetTransfer.fromJson(Map<String, dynamic> json) {
    final kind = TradeAssetKind.values.firstWhere(
      (e) => e.name == json['kind'],
      orElse: () => throw const FormatException('Unknown trade asset kind'),
    );
    final from = TeamId(_requiredString(json, 'from'));
    final to = TeamId(_requiredString(json, 'to'));
    switch (kind) {
      case TradeAssetKind.player:
        return TradeAssetTransfer.player(
          playerId: PlayerId(_requiredString(json, 'playerId')),
          contractId: _requiredString(json, 'contractId'),
          from: from,
          to: to,
          startYear: _requiredInt(json, 'startYear'),
          endYear: _requiredInt(json, 'endYear'),
          termsDigest: _requiredString(json, 'termsDigest'),
        );
      case TradeAssetKind.pick:
        return TradeAssetTransfer.pick(
          draftYear: _requiredInt(json, 'draftYear'),
          overallPick: _requiredInt(json, 'overallPick'),
          originalOwner: TeamId(_requiredString(json, 'originalOwner')),
          from: from,
          to: to,
        );
      case TradeAssetKind.rights:
        return TradeAssetTransfer.rights(
          prospectId: PlayerId(_requiredString(json, 'playerId')),
          draftYear: _requiredInt(json, 'draftYear'),
          overallPick: _requiredInt(json, 'overallPick'),
          originalOwner: TeamId(_requiredString(json, 'originalOwner')),
          from: from,
          to: to,
        );
    }
  }

  static String _requiredString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('Malformed trade asset field $key');
    }
    return value;
  }

  static int _requiredInt(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! int) {
      throw FormatException('Malformed trade asset field $key');
    }
    return value;
  }
}

typedef PlayerTradeTransfer = ({
  PlayerId playerId,
  String contractId,
  TeamId from,
  TeamId to,
  int startYear,
  int endYear,
  String termsDigest,
});

typedef TradePayrollImpact = ({int capPayrollDelta, int cashPayrollDelta});

final class TradeRecord {
  TradeRecord({
    required this.seasonYear,
    required this.sequence,
    required this.firstTeam,
    required this.secondTeam,
    Iterable<PlayerTradeTransfer> transfers = const [],
    Iterable<TradeAssetTransfer>? assets,
    required this.firstTeamImpact,
  }) : assets = List.unmodifiable(
         (assets ??
                 transfers.map(
                   (t) => TradeAssetTransfer.player(
                     playerId: t.playerId,
                     contractId: t.contractId,
                     from: t.from,
                     to: t.to,
                     startYear: t.startYear,
                     endYear: t.endYear,
                     termsDigest: t.termsDigest,
                   ),
                 ))
             .toList()
           ..sort(compareAssets),
       ) {
    validate();
  }

  final int seasonYear;
  final int sequence;
  final TeamId firstTeam;
  final TeamId secondTeam;
  final List<TradeAssetTransfer> assets;

  List<PlayerTradeTransfer> get transfers => [
    for (final a in assets)
      if (a.kind == TradeAssetKind.player)
        (
          playerId: a.playerId!,
          contractId: a.contractId!,
          from: a.from,
          to: a.to,
          startYear: a.startYear!,
          endYear: a.endYear!,
          termsDigest: a.termsDigest!,
        ),
  ];

  final TradePayrollImpact firstTeamImpact;
  CareerPhase get phase => CareerPhase.openingOffseason;
  String get id => 'trade-$seasonYear-$sequence';
  static int compareAssets(TradeAssetTransfer a, TradeAssetTransfer b) {
    final byKind = a.kind.index.compareTo(b.kind.index);
    return byKind != 0 ? byKind : a.canonicalKey.compareTo(b.canonicalKey);
  }

  void validate() {
    if (seasonYear < 1 ||
        sequence < 1 ||
        firstTeam == secondTeam ||
        assets.isEmpty ||
        assets.map((a) => a.canonicalKey).toSet().length != assets.length ||
        assets.any(
          (a) =>
              a.from == a.to ||
              !((a.from == firstTeam && a.to == secondTeam) ||
                  (a.from == secondTeam && a.to == firstTeam)),
        ) ||
        !assets.any((a) => a.from == firstTeam) ||
        !assets.any((a) => a.from == secondTeam)) {
      throw FormatException('Invalid trade receipt $id');
    }
    final sorted = assets.toList()..sort(compareAssets);
    for (var i = 0; i < assets.length; i++) {
      if (compareAssets(assets[i], sorted[i]) != 0) {
        throw FormatException('Noncanonical trade assets in $id');
      }
    }
    final playerIds = <PlayerId>{};
    final contractIds = <String>{};
    for (final a in assets) {
      if (a.kind == TradeAssetKind.player) {
        if (a.playerId == null ||
            a.contractId == null ||
            a.startYear == null ||
            a.endYear == null ||
            a.termsDigest == null ||
            a.startYear! < 1 ||
            a.startYear! > seasonYear ||
            a.endYear! < seasonYear ||
            a.endYear! - a.startYear! >= PlayerContract.maxDurationYears ||
            !RegExp(r'^[0-9a-f]{64}$').hasMatch(a.termsDigest!)) {
          throw FormatException('Invalid player asset in $id');
        }
        if (!playerIds.add(a.playerId!) || !contractIds.add(a.contractId!)) {
          throw FormatException(
            'Duplicate player or contract in trade receipt $id',
          );
        }
      } else if (a.draftYear == null ||
          a.draftYear! > seasonYear ||
          (a.kind == TradeAssetKind.pick && a.draftYear != seasonYear) ||
          a.overallPick == null ||
          a.overallPick! < 1 ||
          a.overallPick! > 60 ||
          a.originalOwner == null) {
        throw FormatException('Invalid draft asset in $id');
      } else if (a.kind == TradeAssetKind.rights &&
          !playerIds.add(a.playerId!)) {
        throw FormatException('Duplicate player identity in trade receipt $id');
      }
    }
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'seasonYear': seasonYear,
    'sequence': sequence,
    'phase': 'openingOffseason',
    'firstTeam': firstTeam.value,
    'secondTeam': secondTeam.value,
    'firstTeamImpact': {
      'capPayrollDelta': firstTeamImpact.capPayrollDelta,
      'cashPayrollDelta': firstTeamImpact.cashPayrollDelta,
    },
    'assets': [for (final asset in assets) asset.toJson()],
  };

  factory TradeRecord.fromJson(Map<String, dynamic> json) {
    final year = json['seasonYear'];
    final sequence = json['sequence'];
    final impact = json['firstTeamImpact'];
    final rawAssets = json['assets'];
    if (year is! int ||
        sequence is! int ||
        impact is! Map<String, dynamic> ||
        impact['capPayrollDelta'] is! int ||
        impact['cashPayrollDelta'] is! int ||
        rawAssets is! List ||
        json['phase'] != 'openingOffseason') {
      throw const FormatException('Malformed trade receipt');
    }
    final assets = [
      for (final raw in rawAssets)
        if (raw is Map<String, dynamic>)
          TradeAssetTransfer.fromJson(raw)
        else
          throw const FormatException('Malformed trade asset'),
    ];
    final sorted = assets.toList()..sort(TradeRecord.compareAssets);
    for (var i = 0; i < assets.length; i++) {
      if (TradeRecord.compareAssets(assets[i], sorted[i]) != 0) {
        throw const FormatException('Trade assets are not canonical');
      }
    }
    final result = TradeRecord(
      seasonYear: year,
      sequence: sequence,
      firstTeam: TeamId(_requiredString(json, 'firstTeam')),
      secondTeam: TeamId(_requiredString(json, 'secondTeam')),
      assets: assets,
      firstTeamImpact: (
        capPayrollDelta: impact['capPayrollDelta'] as int,
        cashPayrollDelta: impact['cashPayrollDelta'] as int,
      ),
    );
    if (json['id'] != result.id) {
      throw FormatException('Invalid trade receipt identity ${json['id']}');
    }
    return result;
  }

  static String _requiredString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('Malformed trade receipt field $key');
    }
    return value;
  }

  static String termsDigest(
    PlayerContract contract,
    ContractFinancials schedule,
  ) => sha256
      .convert(
        utf8.encode(
          jsonEncode([
            contract.id,
            contract.playerId.value,
            contract.category.jsonValue,
            contract.startYear,
            contract.durationYears,
            contract.source.jsonValue,
            contract.rookieContractId,
            schedule.signedYear,
            schedule.guaranteedYears,
            schedule.annualSalaries,
          ]),
        ),
      )
      .toString();
}

import 'ids.dart';
import 'rookie_contract.dart';

/// Authoritative record of every signed drafted rookie in a career.
///
/// Keyed by prospect [PlayerId]. Draft rights remain the sole authority on
/// unsigned ownership; this ledger only records that a signing occurred.
final class RookieSigningLedger {
  RookieSigningLedger({required Map<String, RookieContract> contracts})
    : contracts = Map.unmodifiable(contracts) {
    _validateStructure();
  }

  factory RookieSigningLedger.empty() =>
      RookieSigningLedger(contracts: const {});

  factory RookieSigningLedger.fromJson(Map<String, dynamic> json) {
    final rawContracts = json['contracts'];
    if (rawContracts is! Map<String, dynamic>) {
      throw const FormatException('Malformed RookieSigningLedger JSON');
    }
    final parsed = <String, RookieContract>{};
    for (final entry in rawContracts.entries) {
      final rawContract = entry.value;
      if (rawContract is! Map<String, dynamic>) {
        throw const FormatException('Malformed rookie contract record');
      }
      parsed[entry.key] = RookieContract.fromJson(rawContract);
    }
    return RookieSigningLedger(contracts: parsed);
  }

  final Map<String, RookieContract> contracts;

  int get length => contracts.length;

  bool get isEmpty => contracts.isEmpty;

  bool isSigned(PlayerId playerId) => contracts.containsKey(playerId.value);

  RookieContract? forPlayer(PlayerId playerId) => contracts[playerId.value];

  /// Contracts in canonical draft order for deterministic serialization.
  List<RookieContract> get ordered {
    final ordered = contracts.values.toList()
      ..sort((a, b) {
        final byPick = a.overallPick.compareTo(b.overallPick);
        return byPick != 0
            ? byPick
            : a.playerId.value.compareTo(b.playerId.value);
      });
    return List.unmodifiable(ordered);
  }

  RookieSigningLedger withContract(RookieContract contract) {
    contract.validate();
    if (contracts.containsKey(contract.playerId.value)) {
      throw StateError(
        'Prospect ${contract.playerId.value} has already signed a rookie contract',
      );
    }
    return RookieSigningLedger(
      contracts: {...contracts, contract.playerId.value: contract},
    );
  }

  void _validateStructure() {
    final seenIds = <String>{};
    for (final entry in contracts.entries) {
      final contract = entry.value;
      contract.validate();
      if (entry.key != contract.playerId.value) {
        throw const FormatException(
          'Rookie contract ledger key does not match contract player',
        );
      }
      if (!seenIds.add(contract.id)) {
        throw const FormatException('Duplicate rookie contract ID');
      }
    }
  }

  Map<String, dynamic> toJson() => {
    'contracts': {
      for (final contract in ordered)
        contract.playerId.value: contract.toJson(),
    },
  };
}

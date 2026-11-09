import '../models/position.dart';
import 'action_intent.dart';
import 'offensive_role.dart';

/// Immutable passive observation of one selected field-goal decision.
///
/// Lists are defensive unmodifiable copies. The observer receives no engine
/// state and is never included in the event ledger or fingerprint.
final class ShotDecisionTrace {
  ShotDecisionTrace({
    required this.teamId,
    required List<String> offensiveLineupIds,
    required this.primaryCreatorId,
    required this.secondaryCreatorId,
    required this.shooterId,
    required this.shooterRole,
    required this.creationScore,
    required List<int> rawUsageWeights,
    required List<int> adjustedUsageWeights,
    required this.phase,
    required this.occupiedSlot,
    required List<int> rawZoneWeights,
    required List<int> normalizedZoneWeights,
    required this.selectedZone,
    required this.shotSuccessBasisPoints,
  }) : rawUsageWeights = List<int>.unmodifiable(rawUsageWeights),
       adjustedUsageWeights = List<int>.unmodifiable(adjustedUsageWeights),
       rawZoneWeights = List<int>.unmodifiable(rawZoneWeights),
       normalizedZoneWeights = List<int>.unmodifiable(normalizedZoneWeights),
       offensiveLineupIds = List<String>.unmodifiable(offensiveLineupIds);

  final String teamId;
  final List<String> offensiveLineupIds;
  final String primaryCreatorId;
  final String secondaryCreatorId;
  final String shooterId;
  final OffensiveRole shooterRole;
  final int creationScore;
  final List<int> rawUsageWeights;
  final List<int> adjustedUsageWeights;
  final PhaseKind phase;
  final Position occupiedSlot;
  final List<int> rawZoneWeights;
  final List<int> normalizedZoneWeights;
  final ShotZone selectedZone;
  final int shotSuccessBasisPoints;
}

import 'ids.dart';

/// Outcome of one AI franchise's rookie signing evaluation.
enum AiSigningDecisionType {
  signedStandard('signedStandard'),
  signedTwoWay('signedTwoWay'),
  deferred('deferred');

  const AiSigningDecisionType(this.jsonValue);
  final String jsonValue;

  static AiSigningDecisionType fromJson(String value) => values.firstWhere(
    (e) => e.jsonValue == value || e.name == value,
    orElse: () =>
        throw FormatException('Unknown AI signing decision type: $value'),
  );
}

/// Auditable reason attached to an AI signing decision.
enum AiSigningReason {
  signedStandardNeed('signedStandardNeed'),
  signedStandardQuality('signedStandardQuality'),
  signedTwoWayDevelopment('signedTwoWayDevelopment'),
  signedExistingContract('signedExistingContract'),
  deferredLowFit('deferredLowFit'),
  deferredNoStandardSlot('deferredNoStandardSlot'),
  deferredNoTwoWaySlot('deferredNoTwoWaySlot'),
  deferredRosterFull('deferredRosterFull');

  const AiSigningReason(this.jsonValue);
  final String jsonValue;

  static AiSigningReason fromJson(String value) => values.firstWhere(
    (e) => e.jsonValue == value || e.name == value,
    orElse: () => throw FormatException('Unknown AI signing reason: $value'),
  );
}

/// Persistent record of one evaluated AI-owned draft right.
final class AiSigningDecision {
  const AiSigningDecision({
    required this.teamId,
    required this.prospectId,
    required this.draftSeasonYear,
    required this.overallPick,
    required this.decision,
    required this.reason,
    this.contractId,
  });

  factory AiSigningDecision.fromJson(Map<String, dynamic> json) {
    final teamId = json['teamId'];
    final prospectId = json['prospectId'];
    final draftSeasonYear = json['draftSeasonYear'];
    final overallPick = json['overallPick'];
    final decision = json['decision'];
    final reason = json['reason'];
    final contractId = json['contractId'];

    if (teamId is! String ||
        prospectId is! String ||
        draftSeasonYear is! int ||
        overallPick is! int ||
        decision is! String ||
        reason is! String ||
        (contractId != null && contractId is! String)) {
      throw const FormatException('Malformed AiSigningDecision JSON');
    }

    return AiSigningDecision(
      teamId: TeamId(teamId),
      prospectId: PlayerId(prospectId),
      draftSeasonYear: draftSeasonYear,
      overallPick: overallPick,
      decision: AiSigningDecisionType.fromJson(decision),
      reason: AiSigningReason.fromJson(reason),
      contractId: contractId as String?,
    )..validate();
  }

  final TeamId teamId;
  final PlayerId prospectId;
  final int draftSeasonYear;
  final int overallPick;
  final AiSigningDecisionType decision;
  final AiSigningReason reason;
  final String? contractId;

  bool get isSigned => decision != AiSigningDecisionType.deferred;

  void validate() {
    if (teamId.value.trim().isEmpty || prospectId.value.trim().isEmpty) {
      throw const FormatException(
        'AI signing decision requires team and player',
      );
    }
    if (draftSeasonYear < 1 || overallPick < 1 || overallPick > 60) {
      throw const FormatException('Invalid AI signing decision draft position');
    }
    switch (decision) {
      case AiSigningDecisionType.signedStandard:
        if (reason != AiSigningReason.signedStandardNeed &&
            reason != AiSigningReason.signedStandardQuality &&
            reason != AiSigningReason.signedExistingContract) {
          throw const FormatException(
            'Standard signing decision has an incompatible reason',
          );
        }
      case AiSigningDecisionType.signedTwoWay:
        if (reason != AiSigningReason.signedTwoWayDevelopment &&
            reason != AiSigningReason.signedExistingContract) {
          throw const FormatException(
            'Two-way signing decision has an incompatible reason',
          );
        }
      case AiSigningDecisionType.deferred:
        if (reason != AiSigningReason.deferredLowFit &&
            reason != AiSigningReason.deferredNoStandardSlot &&
            reason != AiSigningReason.deferredNoTwoWaySlot &&
            reason != AiSigningReason.deferredRosterFull) {
          throw const FormatException(
            'Deferred AI decision has an incompatible reason',
          );
        }
    }
    if (isSigned) {
      if (contractId == null || contractId!.trim().isEmpty) {
        throw const FormatException(
          'Signed AI decision requires a contract reference',
        );
      }
    } else if (contractId != null) {
      throw const FormatException(
        'Deferred AI decision cannot reference a contract',
      );
    }
  }

  Map<String, dynamic> toJson() => {
    'teamId': teamId.value,
    'prospectId': prospectId.value,
    'draftSeasonYear': draftSeasonYear,
    'overallPick': overallPick,
    'decision': decision.jsonValue,
    'reason': reason.jsonValue,
    if (contractId != null) 'contractId': contractId,
  };
}

/// Persistent AI signing state keyed by prospect identity.
///
/// Absence of a decision means "not evaluated"; a deferred record means
/// "evaluated and intentionally kept unsigned".
final class AiRookieSigningState {
  AiRookieSigningState({required Map<String, AiSigningDecision> decisions})
    : decisions = Map.unmodifiable(decisions) {
    _validateStructure();
  }

  factory AiRookieSigningState.empty() =>
      AiRookieSigningState(decisions: const {});

  factory AiRookieSigningState.fromJson(Map<String, dynamic> json) {
    final rawDecisions = json['decisions'];
    if (rawDecisions is! Map<String, dynamic>) {
      throw const FormatException('Malformed AiRookieSigningState JSON');
    }
    final parsed = <String, AiSigningDecision>{};
    for (final entry in rawDecisions.entries) {
      final rawDecision = entry.value;
      if (rawDecision is! Map<String, dynamic>) {
        throw const FormatException('Malformed AI signing decision record');
      }
      parsed[entry.key] = AiSigningDecision.fromJson(rawDecision);
    }
    return AiRookieSigningState(decisions: parsed);
  }

  final Map<String, AiSigningDecision> decisions;

  int get length => decisions.length;

  bool get isEmpty => decisions.isEmpty;

  bool hasDecision(PlayerId playerId) => decisions.containsKey(playerId.value);

  AiSigningDecision? forProspect(PlayerId playerId) =>
      decisions[playerId.value];

  /// Decisions in canonical draft order for deterministic serialization.
  List<AiSigningDecision> get ordered {
    final ordered = decisions.values.toList()
      ..sort((a, b) {
        final byPick = a.overallPick.compareTo(b.overallPick);
        return byPick != 0
            ? byPick
            : a.prospectId.value.compareTo(b.prospectId.value);
      });
    return List.unmodifiable(ordered);
  }

  AiRookieSigningState withDecision(AiSigningDecision decision) {
    decision.validate();
    if (decisions.containsKey(decision.prospectId.value)) {
      throw StateError(
        'Prospect ${decision.prospectId.value} already has an AI signing decision',
      );
    }
    return AiRookieSigningState(
      decisions: {...decisions, decision.prospectId.value: decision},
    );
  }

  void _validateStructure() {
    final contractIds = <String>{};
    for (final entry in decisions.entries) {
      final decision = entry.value;
      decision.validate();
      if (entry.key != decision.prospectId.value) {
        throw const FormatException(
          'AI signing decision key does not match its prospect',
        );
      }
      final contractId = decision.contractId;
      if (contractId != null && !contractIds.add(contractId)) {
        throw const FormatException('Duplicate AI signing contract reference');
      }
    }
  }

  Map<String, dynamic> toJson() => {
    'decisions': {
      for (final decision in ordered)
        decision.prospectId.value: decision.toJson(),
    },
  };
}

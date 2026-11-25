import '../finance/career_finances.dart';
import '../finance/financial_rules.dart';
import '../models/ids.dart';
import '../models/league.dart';
import 'staff_identity_generator.dart';
import 'staff_member.dart';

/// League-wide named staff and the M011 coaching switch.
///
/// Money stays on `StaffCommitment`: every commitment is referenced by exactly
/// one employed or dismissed member, and nothing here stores salary.
final class StaffState {
  StaffState({
    required this.coachingEnabled,
    Iterable<StaffMember> members = const [],
  }) : members = Map.unmodifiable(_index(members));

  /// Coaching disabled and no members.
  factory StaffState.empty() => StaffState(coachingEnabled: false);

  /// Names every existing commitment with a deterministic fictional person,
  /// without changing any cost, term or ownership. Used for new careers and
  /// for migrating pre-v27 saves; expired commitments no longer exist, so no
  /// fictional staff are created for them.
  factory StaffState.incumbentsFor({
    required CareerFinances finances,
    required int generationSeed,
  }) => StaffState(
    coachingEnabled: false,
    members: [
      for (final commitment in finances.staffCommitments.values)
        StaffIdentityGenerator.person(
          id: incumbentIdFor(commitment.id),
          generationSeed: generationSeed,
          role: commitment.category,
          tier: commitment.tier,
          status: StaffEmploymentStatus.employed,
          teamId: commitment.teamId,
          commitmentId: commitment.id,
        ),
    ],
  );

  factory StaffState.fromJson(Object? raw) {
    if (raw is! Map<String, dynamic> ||
        raw.keys.any((k) => k != 'coachingEnabled' && k != 'members') ||
        raw['coachingEnabled'] is! bool ||
        raw['members'] is! List) {
      throw const FormatException('Malformed staff state');
    }
    final members = [
      for (final entry in raw['members'] as List) StaffMember.fromJson(entry),
    ];
    final ids = <String>{};
    for (final member in members) {
      if (!ids.add(member.id)) {
        throw FormatException('Duplicate staff member id ${member.id}');
      }
    }
    return StaffState(
      coachingEnabled: raw['coachingEnabled'] as bool,
      members: members,
    );
  }

  static String incumbentIdFor(String commitmentId) => 'person-$commitmentId';

  final bool coachingEnabled;

  /// Members keyed by id, canonically sorted.
  final Map<String, StaffMember> members;

  static Map<String, StaffMember> _index(Iterable<StaffMember> members) {
    final byId = <String, StaffMember>{};
    for (final member in members) {
      if (byId.containsKey(member.id)) {
        throw FormatException('Duplicate staff member id ${member.id}');
      }
      byId[member.id] = member;
    }
    return {for (final id in byId.keys.toList()..sort()) id: byId[id]!};
  }

  /// The employed head coach of [teamId], if any.
  StaffMember? employedHeadCoach(TeamId teamId) => members.values
      .where(
        (m) =>
            m.isEmployed &&
            m.role == StaffCategory.headCoach &&
            m.teamId == teamId,
      )
      .firstOrNull;

  /// Member linked to [commitmentId] (employed or dismissed), if any.
  StaffMember? memberForCommitment(String commitmentId) =>
      members.values.where((m) => m.commitmentId == commitmentId).firstOrNull;

  StaffState copyWith({
    bool? coachingEnabled,
    Iterable<StaffMember>? members,
  }) => StaffState(
    coachingEnabled: coachingEnabled ?? this.coachingEnabled,
    members: members ?? this.members.values,
  );

  StaffState withMember(StaffMember member) =>
      copyWith(members: {...members, member.id: member}.values);

  /// Year N → N+1: members whose commitment did not carry over lose their
  /// team and become available; continuing links are kept unchanged.
  StaffState rolledOver(CareerFinances nextFinances) => copyWith(
    members: [
      for (final member in members.values)
        if (member.commitmentId != null &&
            !nextFinances.staffCommitments.containsKey(member.commitmentId))
          member.withEmployment(status: StaffEmploymentStatus.available)
        else
          member,
    ],
  );

  /// Cross-record invariants against the authoritative finances.
  void validate({required CareerFinances finances, required League league}) {
    final teamIds = {for (final t in league.teams) t.id.value};
    final linked = <String, String>{};
    final coachTeams = <String>{};
    for (final member in members.values) {
      member.validate();
      final commitmentId = member.commitmentId;
      if (commitmentId == null) continue;
      final commitment = finances.staffCommitments[commitmentId];
      if (commitment == null) {
        throw FormatException(
          'Staff member ${member.id} references missing commitment '
          '$commitmentId',
        );
      }
      if (commitment.teamId != member.teamId ||
          commitment.category != member.role ||
          commitment.tier != member.tier ||
          !teamIds.contains(member.teamId!.value)) {
        throw FormatException(
          'Staff member ${member.id} does not match commitment $commitmentId',
        );
      }
      final prior = linked[commitmentId];
      if (prior != null) {
        throw FormatException(
          'Commitment $commitmentId is linked to $prior and ${member.id}',
        );
      }
      linked[commitmentId] = member.id;
      if (member.isEmployed && member.role == StaffCategory.headCoach) {
        if (!coachTeams.add(member.teamId!.value)) {
          throw FormatException(
            'Team ${member.teamId!.value} has more than one employed head coach',
          );
        }
      }
    }
    for (final commitmentId in finances.staffCommitments.keys) {
      if (!linked.containsKey(commitmentId)) {
        throw FormatException(
          'Staff commitment $commitmentId has no named staff member',
        );
      }
    }
  }

  Map<String, Object?> toJson() => {
    'coachingEnabled': coachingEnabled,
    'members': [for (final member in members.values) member.toJson()],
  };
}

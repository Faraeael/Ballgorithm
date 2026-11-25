import '../finance/financial_rules.dart';
import '../models/ids.dart';

/// Approved M011 head-coach philosophies. `developmentFocused` is deferred
/// (D4) and deliberately absent.
enum CoachPhilosophy {
  balanced('balanced'),
  starFocused('starFocused'),
  deepRotation('deepRotation'),
  defensiveMinded('defensiveMinded');

  const CoachPhilosophy(this.jsonValue);

  final String jsonValue;

  static CoachPhilosophy fromJson(Object? value) => values.firstWhere(
    (p) => p.jsonValue == value,
    orElse: () => throw FormatException('Unknown coach philosophy: $value'),
  );
}

/// Employment of a named staff member.
///
/// * `employed`: holds authority and is paid through [StaffMember.commitmentId].
/// * `dismissed`: no authority, but the franchise still pays the linked
///   commitment until it expires (D6).
/// * `available`: no team and no commitment; may be hired.
enum StaffEmploymentStatus {
  employed('employed'),
  dismissed('dismissed'),
  available('available');

  const StaffEmploymentStatus(this.jsonValue);

  final String jsonValue;

  static StaffEmploymentStatus fromJson(Object? value) => values.firstWhere(
    (s) => s.jsonValue == value,
    orElse: () => throw FormatException('Unknown staff status: $value'),
  );
}

/// A fictional, individually identifiable staff member (M011).
///
/// Holds no money: salary and term live only on the linked `StaffCommitment`
/// (the financial authority), so salaries cannot be double counted.
final class StaffMember {
  StaffMember({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.age,
    required this.role,
    required this.tier,
    required this.experienceYears,
    required this.status,
    this.philosophy,
    this.teamId,
    this.commitmentId,
  }) {
    validate();
  }

  factory StaffMember.fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('Malformed StaffMember JSON');
    }
    const allowed = {
      'id',
      'firstName',
      'lastName',
      'age',
      'role',
      'tier',
      'experienceYears',
      'status',
      'philosophy',
      'teamId',
      'commitmentId',
    };
    if (raw.keys.any((k) => !allowed.contains(k))) {
      throw const FormatException('StaffMember has unknown keys');
    }
    final id = raw['id'];
    final first = raw['firstName'];
    final last = raw['lastName'];
    final age = raw['age'];
    final experience = raw['experienceYears'];
    final teamId = raw['teamId'];
    final commitmentId = raw['commitmentId'];
    if (id is! String ||
        first is! String ||
        last is! String ||
        age is! int ||
        experience is! int ||
        raw['role'] is! String ||
        raw['tier'] is! String ||
        (teamId != null && teamId is! String) ||
        (commitmentId != null && commitmentId is! String)) {
      throw const FormatException('Malformed StaffMember JSON');
    }
    final StaffCategory role;
    final StaffTier tier;
    try {
      role = StaffCategory.fromJson(raw['role'] as String);
      tier = StaffTier.fromJson(raw['tier'] as String);
    } on ArgumentError catch (e) {
      throw FormatException('Malformed StaffMember JSON: ${e.message}');
    }
    return StaffMember(
      id: id,
      firstName: first,
      lastName: last,
      age: age,
      role: role,
      tier: tier,
      experienceYears: experience,
      status: StaffEmploymentStatus.fromJson(raw['status']),
      philosophy: raw.containsKey('philosophy')
          ? CoachPhilosophy.fromJson(raw['philosophy'])
          : null,
      teamId: teamId == null ? null : TeamId(teamId as String),
      commitmentId: commitmentId as String?,
    );
  }

  final String id;
  final String firstName;
  final String lastName;
  final int age;
  final StaffCategory role;
  final StaffTier tier;
  final int experienceYears;
  final StaffEmploymentStatus status;

  /// Present for head coaches only.
  final CoachPhilosophy? philosophy;
  final TeamId? teamId;
  final String? commitmentId;

  String get fullName => '$firstName $lastName';
  bool get isEmployed => status == StaffEmploymentStatus.employed;
  bool get isAvailable => status == StaffEmploymentStatus.available;

  /// Structural invariants; cross-record checks live in `StaffState`.
  void validate() {
    if (id.trim().isEmpty || firstName.trim().isEmpty || lastName.isEmpty) {
      throw FormatException('StaffMember "$id" requires id and name');
    }
    if (age < 21 || age > 80) {
      throw FormatException('StaffMember $id age $age outside 21..80');
    }
    if (experienceYears < 0 || experienceYears > age - 20) {
      throw FormatException(
        'StaffMember $id experience $experienceYears invalid for age $age',
      );
    }
    if ((role == StaffCategory.headCoach) != (philosophy != null)) {
      throw FormatException(
        'StaffMember $id: philosophy is required for head coaches only',
      );
    }
    final linked = teamId != null && commitmentId != null;
    final unlinked = teamId == null && commitmentId == null;
    if (status == StaffEmploymentStatus.available ? !unlinked : !linked) {
      throw FormatException(
        'StaffMember $id: status ${status.jsonValue} has inconsistent '
        'team/commitment links',
      );
    }
  }

  StaffMember withEmployment({
    required StaffEmploymentStatus status,
    TeamId? teamId,
    String? commitmentId,
  }) => StaffMember(
    id: id,
    firstName: firstName,
    lastName: lastName,
    age: age,
    role: role,
    tier: tier,
    experienceYears: experienceYears,
    status: status,
    philosophy: philosophy,
    teamId: teamId,
    commitmentId: commitmentId,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'firstName': firstName,
    'lastName': lastName,
    'age': age,
    'role': role.jsonValue,
    'tier': tier.jsonValue,
    'experienceYears': experienceYears,
    'status': status.jsonValue,
    if (philosophy != null) 'philosophy': philosophy!.jsonValue,
    if (teamId != null) 'teamId': teamId!.value,
    if (commitmentId != null) 'commitmentId': commitmentId,
  };

  @override
  bool operator ==(Object other) =>
      other is StaffMember &&
      other.id == id &&
      other.firstName == firstName &&
      other.lastName == lastName &&
      other.age == age &&
      other.role == role &&
      other.tier == tier &&
      other.experienceYears == experienceYears &&
      other.status == status &&
      other.philosophy == philosophy &&
      other.teamId == teamId &&
      other.commitmentId == commitmentId;

  @override
  int get hashCode => Object.hash(
    id,
    firstName,
    lastName,
    age,
    role,
    tier,
    experienceYears,
    status,
    philosophy,
    teamId,
    commitmentId,
  );
}

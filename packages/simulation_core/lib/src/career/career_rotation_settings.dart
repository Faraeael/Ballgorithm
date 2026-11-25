import '../models/ids.dart';
import '../simulation/game_rules.dart';
import '../simulation/rotation_plan.dart';

/// Who decides the human franchise's starters and playing time.
enum CareerRotationMode {
  /// Default lineup and balanced rotation, identical to AI franchises.
  auto('auto'),

  /// The saved starters, preset and (for custom) integer-second targets.
  manual('manual');

  const CareerRotationMode(this.jsonValue);

  final String jsonValue;
}

/// Persisted lineup and rotation preferences for the human franchise (M010).
///
/// Stores stable player IDs only and is never bound to a roster at decode
/// time: a structurally valid manual plan whose players have since left the
/// standard roster is *obsolete*, not malformed, and is preserved for explicit
/// reconciliation by `CareerRotationService`.
final class CareerRotationSettings {
  const CareerRotationSettings._({
    required this.mode,
    required this.starters,
    required this.preset,
    required this.customTargets,
  });

  /// Automatic mode; existing careers decode to this.
  static const CareerRotationSettings auto = CareerRotationSettings._(
    mode: CareerRotationMode.auto,
    starters: [],
    preset: RotationPreset.balanced,
    customTargets: {},
  );

  /// Validated manual settings.
  ///
  /// [starters] are PG..C slot-ordered. [customTargets] is required for
  /// [RotationPreset.custom] and forbidden otherwise. A player absent from
  /// [customTargets] is "unassigned"; an explicit `0` is an intentional zero.
  factory CareerRotationSettings.manual({
    required List<PlayerId> starters,
    required RotationPreset preset,
    Map<String, int>? customTargets,
  }) {
    if (starters.length != 5) {
      throw FormatException(
        'Manual rotation requires exactly 5 starters, got ${starters.length}',
      );
    }
    final seen = <String>{};
    for (final id in starters) {
      if (id.value.trim().isEmpty || !seen.add(id.value)) {
        throw FormatException(
          'Manual rotation starters must be unique non-empty IDs: ${id.value}',
        );
      }
    }
    final isCustom = preset == RotationPreset.custom;
    if (isCustom != (customTargets != null)) {
      throw const FormatException(
        'customTargets is required for custom and forbidden otherwise',
      );
    }
    final cap = RotationPlan.regulationCap(GameRules.standard);
    final sorted = <String, int>{};
    if (customTargets != null) {
      for (final key in customTargets.keys.toList()..sort()) {
        final seconds = customTargets[key]!;
        if (key.trim().isEmpty || seconds < 0 || seconds > cap) {
          throw FormatException(
            'Invalid custom target for "$key": $seconds (allowed 0..$cap)',
          );
        }
        sorted[key] = seconds;
      }
    }
    return CareerRotationSettings._(
      mode: CareerRotationMode.manual,
      starters: List.unmodifiable(starters),
      preset: preset,
      customTargets: Map.unmodifiable(sorted),
    );
  }

  /// Strict decoder: rejects malformed data with a [FormatException].
  factory CareerRotationSettings.fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('Malformed userRotation: expected object');
    }
    final mode = raw['mode'];
    if (mode == CareerRotationMode.auto.jsonValue) {
      if (raw.length != 1) {
        throw const FormatException('Automatic userRotation has extra keys');
      }
      return auto;
    }
    if (mode != CareerRotationMode.manual.jsonValue) {
      throw FormatException('Unknown userRotation mode: $mode');
    }
    const allowed = {'mode', 'starters', 'preset', 'customTargets'};
    if (raw.keys.any((key) => !allowed.contains(key))) {
      throw const FormatException('Manual userRotation has unknown keys');
    }
    final rawStarters = raw['starters'];
    if (rawStarters is! List || rawStarters.any((id) => id is! String)) {
      throw const FormatException('Malformed userRotation starters');
    }
    final rawPreset = raw['preset'];
    final preset = RotationPreset.values
        .where((value) => value.jsonValue == rawPreset)
        .firstOrNull;
    if (preset == null) {
      throw FormatException('Unknown userRotation preset: $rawPreset');
    }
    final rawTargets = raw['customTargets'];
    Map<String, int>? targets;
    if (raw.containsKey('customTargets')) {
      if (rawTargets is! Map<String, dynamic> ||
          rawTargets.values.any((value) => value is! int)) {
        throw const FormatException('Malformed userRotation customTargets');
      }
      targets = rawTargets.cast<String, int>();
    }
    return CareerRotationSettings.manual(
      starters: [for (final id in rawStarters.cast<String>()) PlayerId(id)],
      preset: preset,
      customTargets: targets,
    );
  }

  final CareerRotationMode mode;

  /// PG..C slot-ordered starters; empty in [CareerRotationMode.auto].
  final List<PlayerId> starters;
  final RotationPreset preset;

  /// Canonically sorted custom targets; empty unless [preset] is custom.
  final Map<String, int> customTargets;

  bool get isManual => mode == CareerRotationMode.manual;

  Map<String, Object?> toJson() => isManual
      ? {
          'mode': mode.jsonValue,
          'starters': [for (final id in starters) id.value],
          'preset': preset.jsonValue,
          if (preset == RotationPreset.custom) 'customTargets': customTargets,
        }
      : {'mode': mode.jsonValue};

  @override
  bool operator ==(Object other) =>
      other is CareerRotationSettings &&
      other.mode == mode &&
      other.preset == preset &&
      _listEquals(other.starters, starters) &&
      _mapEquals(other.customTargets, customTargets);

  @override
  int get hashCode => Object.hash(
    mode,
    preset,
    Object.hashAll(starters),
    Object.hashAll(
      customTargets.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );

  static bool _listEquals(List<PlayerId> a, List<PlayerId> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static bool _mapEquals(Map<String, int> a, Map<String, int> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }
}

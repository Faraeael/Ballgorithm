import 'dart:io';

import 'package:test/test.dart';

/// Guards constitution rule 2: the domain stays independent of Flutter,
/// Flame, persistence and network packages.
void main() {
  test('domain library has no framework or persistence imports', () {
    final lib = Directory('lib');
    expect(lib.existsSync(), isTrue, reason: 'run from the package root');

    const forbidden = [
      'package:flutter',
      'dart:ui',
      'package:flame',
      'package:sqflite',
      'package:path_provider',
      'package:shared_preferences',
      'package:http',
      'dart:io',
    ];

    final sources = lib
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    expect(sources, isNotEmpty);
    for (final file in sources) {
      final source = file.readAsStringSync();
      for (final dependency in forbidden) {
        expect(
          source.contains(dependency),
          isFalse,
          reason: '${file.path} references $dependency',
        );
      }
    }
  });

  test('dormant M006 policy code has no production call site', () {
    // Guards DD-M006-08: T01-T03 ship dormant code until T04 activates it in one
    // commit and removes this test. Each identifier may appear only in the file
    // that defines it, its test and the package barrel.
    final policies = <String, String>{
      'OffensiveRoleRanking': 'offensive_role.dart',
      'OffensiveOpportunity': 'offensive_opportunity.dart',
      'DerivedShotPreference': 'shot_preference.dart',
    };
    final sources = Directory('lib/src')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    for (final entry in policies.entries) {
      for (final file in sources) {
        if (file.path.endsWith(entry.value)) continue;
        expect(
          file.readAsStringSync().contains(entry.key),
          isFalse,
          reason: '${file.path} calls the dormant policy ${entry.key}',
        );
      }
    }
  });
}

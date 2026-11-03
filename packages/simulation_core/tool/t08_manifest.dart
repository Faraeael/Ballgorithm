import 'dart:convert';
import 'dart:io';

import 't08_common.dart';

/// Writes the frozen T08 manifest and prints its SHA-256 and validation report.
///
/// Usage: `dart run tool/t08_manifest.dart --out=<path>`
void main(List<String> args) {
  final out =
      _arg(args, 'out') ?? 'specs/004-player-participation/t08/t08-seeds.csv';
  final csv = t08ManifestCsv();
  final slots = parseT08Manifest(csv);
  validateT08Slots(slots);

  final file = File(out);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(csv);

  final bytes = file.readAsBytesSync();
  print(
    const JsonEncoder.withIndent('  ').convert({
      'manifestPath': file.absolute.path,
      'manifestSha256': sha256Hex(utf8.decode(bytes)),
      'rows': slots.length,
      'perMatchup': {
        for (var m = 0; m < t08MatchupCount; m++)
          '$m': slots.where((slot) => slot.matchup == m).length,
      },
      'evenSeedsPerMatchup': {
        for (var m = 0; m < t08MatchupCount; m++)
          '$m': slots
              .where((slot) => slot.matchup == m && slot.seed.isEven)
              .length,
      },
      'seedRange': '${slots.first.seed}..${slots.last.seed}',
    }),
  );
}

String? _arg(List<String> args, String name) {
  for (final arg in args) {
    if (arg.startsWith('--$name=')) return arg.substring(name.length + 3);
  }
  return null;
}

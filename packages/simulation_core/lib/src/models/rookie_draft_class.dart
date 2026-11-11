import 'ids.dart';
import 'position.dart';
import 'rookie_prospect.dart';

/// The complete pool of eligible prospects for an annual rookie draft.
final class RookieDraftClass {
  RookieDraftClass({
    required this.seasonYear,
    required List<RookieProspect> prospects,
  }) : prospects = List.unmodifiable(prospects) {
    validate();
  }

  factory RookieDraftClass.fromJson(Map<String, dynamic> json) {
    final seasonYear = json['seasonYear'] as int?;
    final rawProspects = json['prospects'] as List<dynamic>?;

    if (seasonYear == null || rawProspects == null) {
      throw const FormatException('Malformed RookieDraftClass JSON');
    }

    final prospects = rawProspects
        .map((p) => RookieProspect.fromJson(p as Map<String, dynamic>))
        .toList();

    return RookieDraftClass(seasonYear: seasonYear, prospects: prospects);
  }

  static const int expectedProspectCount = 90;

  final int seasonYear;
  final List<RookieProspect> prospects;

  int get length => prospects.length;

  RookieProspect get rankedFirst =>
      prospects.firstWhere((p) => p.projectedRank == 1);

  RookieProspect? byId(PlayerId id) => prospects
      .cast<RookieProspect?>()
      .firstWhere((p) => p?.id == id, orElse: () => null);

  List<RookieProspect> byPosition(Position position) =>
      prospects.where((p) => p.position == position).toList();

  void validate() {
    if (prospects.length != expectedProspectCount) {
      throw FormatException(
        'Invalid rookie class size: expected $expectedProspectCount, got ${prospects.length}',
      );
    }

    final seenIds = <String>{};
    final seenRanks = <int>{};
    final positionCounts = <Position, int>{};

    for (final prospect in prospects) {
      prospect.validate();

      if (!seenIds.add(prospect.id.value)) {
        throw FormatException('Duplicate prospect ID: ${prospect.id.value}');
      }
      if (!seenRanks.add(prospect.projectedRank)) {
        throw FormatException(
          'Duplicate projected rank: ${prospect.projectedRank}',
        );
      }
      positionCounts[prospect.position] =
          (positionCounts[prospect.position] ?? 0) + 1;
    }

    for (final pos in Position.values) {
      if ((positionCounts[pos] ?? 0) < 5) {
        throw FormatException(
          'Position ${pos.shortName} underrepresented in draft class: ${positionCounts[pos] ?? 0}',
        );
      }
    }
  }

  Map<String, dynamic> toJson() => {
    'seasonYear': seasonYear,
    'prospects': prospects.map((p) => p.toJson()).toList(),
  };
}

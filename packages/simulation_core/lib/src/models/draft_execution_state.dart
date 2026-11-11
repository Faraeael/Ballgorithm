import 'draft_order.dart';
import 'draft_pick.dart';
import 'draft_rights.dart';
import 'draft_selection.dart';
import 'ids.dart';
import 'rookie_draft_class.dart';
import 'rookie_prospect.dart';

/// Lifecycle status of an annual rookie draft.
enum DraftExecutionStatus {
  notStarted('notStarted'),
  inProgress('inProgress'),
  completed('completed');

  const DraftExecutionStatus(this.jsonValue);
  final String jsonValue;

  static DraftExecutionStatus fromJson(String value) => values.firstWhere(
    (e) => e.jsonValue == value || e.name == value,
    orElse: () =>
        throw FormatException('Unknown draft execution status: $value'),
  );
}

/// The authoritative persistent state of a running or completed rookie draft.
final class DraftExecutionState {
  DraftExecutionState({
    required this.status,
    required List<DraftSelection> selections,
    required Map<String, DraftRights> draftRights,
  }) : selections = List.unmodifiable(selections),
       draftRights = Map.unmodifiable(draftRights) {
    _validateStructure();
  }

  factory DraftExecutionState.initial() => DraftExecutionState(
    status: DraftExecutionStatus.notStarted,
    selections: const [],
    draftRights: const {},
  );

  factory DraftExecutionState.fromJson(Map<String, dynamic> json) {
    final rawStatus = json['status'];
    final rawSelections = json['selections'];
    final rawRights = json['draftRights'];
    if (rawStatus is! String ||
        rawSelections is! List ||
        rawRights is! Map<String, dynamic>) {
      throw const FormatException('Malformed DraftExecutionState JSON');
    }
    final selections = <DraftSelection>[];
    for (final selection in rawSelections) {
      if (selection is! Map<String, dynamic>) {
        throw const FormatException('Malformed draft selection record');
      }
      selections.add(DraftSelection.fromJson(selection));
    }
    final rights = <String, DraftRights>{};
    for (final key in rawRights.keys) {
      final record = rawRights[key];
      if (record is! Map<String, dynamic>) {
        throw const FormatException('Malformed draft rights record');
      }
      rights[key] = DraftRights.fromJson(record);
    }
    return DraftExecutionState(
      status: DraftExecutionStatus.fromJson(rawStatus),
      selections: selections,
      draftRights: rights,
    );
  }

  final DraftExecutionStatus status;
  final List<DraftSelection> selections;
  final Map<String, DraftRights> draftRights;

  int get completedSelectionsCount => selections.length;
  bool get isCompleted => status == DraftExecutionStatus.completed;
  bool get isNotStarted => status == DraftExecutionStatus.notStarted;
  bool get isInProgress => status == DraftExecutionStatus.inProgress;

  /// Next pick rank (1..60) or null if draft is finished.
  int? get currentOverallPick => isCompleted ? null : selections.length + 1;

  Set<String> get selectedProspectIds => {
    for (final selection in selections) selection.prospectId.value,
  };

  bool isProspectSelected(PlayerId id) => draftRights.containsKey(id.value);

  List<RookieProspect> availableProspects(RookieDraftClass draftClass) =>
      draftClass.prospects.where((p) => !isProspectSelected(p.id)).toList();

  List<RookieProspect> undraftedProspects(RookieDraftClass draftClass) =>
      availableProspects(draftClass);

  DraftPick? currentPick(DraftOrder order) {
    final pick = currentOverallPick;
    return pick == null ? null : order.pickAt(pick);
  }

  bool isHumanTurn({required DraftOrder order, required TeamId userTeamId}) =>
      isInProgress && currentPick(order)?.currentOwnerTeamId == userTeamId;

  /// Commits exactly one sequential selection; the draft must already be active.
  DraftExecutionState withSelection({
    required DraftSelection selection,
    required DraftRights rights,
  }) {
    if (!isInProgress) {
      throw StateError('Cannot select: draft is not in progress');
    }
    return DraftExecutionState(
      status: selections.length + 1 == 60
          ? DraftExecutionStatus.completed
          : DraftExecutionStatus.inProgress,
      selections: [...selections, selection],
      draftRights: {...draftRights, rights.prospectId.value: rights},
    );
  }

  void _validateStructure() {
    final count = selections.length;
    if (count > 60 ||
        (status == DraftExecutionStatus.notStarted && count != 0) ||
        (status == DraftExecutionStatus.inProgress && count >= 60) ||
        (status == DraftExecutionStatus.completed && count != 60)) {
      throw const FormatException('Draft status and selection count disagree');
    }
    if (draftRights.length != count) {
      throw const FormatException('Draft rights and selection counts disagree');
    }
    final seen = <String>{};
    for (var i = 0; i < count; i++) {
      final selection = selections[i];
      selection.validate();
      if (selection.overallPick != i + 1 ||
          !seen.add(selection.prospectId.value)) {
        throw const FormatException(
          'Draft selections must be sequential and unique',
        );
      }
      if (selection.seasonYear != selections.first.seasonYear) {
        throw const FormatException('Draft selections span different seasons');
      }
      final rights = draftRights[selection.prospectId.value];
      if (rights == null) {
        throw const FormatException(
          'Missing draft rights for selected prospect',
        );
      }
      rights.validate();
      if (rights.prospectId != selection.prospectId ||
          rights.owningTeamId != selection.selectingTeamId ||
          rights.overallPick != selection.overallPick ||
          rights.seasonYear != selection.seasonYear) {
        throw const FormatException('Draft rights do not match selection');
      }
    }
  }

  /// Checks saved records against the authoritative order, class, and career year.
  void validate({
    required DraftOrder order,
    required RookieDraftClass draftClass,
    int? seasonYear,
  }) {
    _validateStructure();
    final expectedYear = seasonYear ?? draftClass.seasonYear;
    if (expectedYear < 1 || draftClass.seasonYear != expectedYear) {
      throw const FormatException(
        'Draft class year does not match career year',
      );
    }
    for (final selection in selections) {
      final pick = order.pickAt(selection.overallPick);
      if (selection.round != pick.round ||
          selection.pickInRound != pick.pickInRound ||
          selection.originalOwnerTeamId != pick.originalOwnerTeamId ||
          selection.selectingTeamId != pick.currentOwnerTeamId ||
          selection.seasonYear != expectedYear) {
        throw const FormatException(
          'Draft selection does not match draft order or year',
        );
      }
      if (draftClass.byId(selection.prospectId) == null) {
        throw const FormatException(
          'Selected prospect not found in draft class',
        );
      }
    }
  }

  Map<String, dynamic> toJson() => {
    'status': status.jsonValue,
    'selections': selections.map((selection) => selection.toJson()).toList(),
    'draftRights': {
      for (final entry in draftRights.entries) entry.key: entry.value.toJson(),
    },
  };
}

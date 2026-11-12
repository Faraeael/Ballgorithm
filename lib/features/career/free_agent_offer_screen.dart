import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:simulation_core/simulation_core.dart';

import 'career_controller.dart';

const _market = FreeAgentMarketValueService();

/// Formal offer form for one available free agent.
class GmFreeAgentOfferScreen extends StatefulWidget {
  const GmFreeAgentOfferScreen({
    super.key,
    required this.controller,
    required this.freeAgentId,
  });

  final GmCareerController controller;
  final PlayerId freeAgentId;

  @override
  State<GmFreeAgentOfferScreen> createState() => _GmFreeAgentOfferScreenState();
}

class _GmFreeAgentOfferScreenState extends State<GmFreeAgentOfferScreen> {
  late RosterCategory _category = RosterCategory.standard;
  late int _durationYears;
  late TextEditingController _salaryController;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final entry = _entry;
    final valuation = _market.estimate(entry.toPublicView());
    _durationYears = valuation.preferredDurationYears;
    _salaryController = TextEditingController(
      text: valuation.estimatedAnnualSalary.toString(),
    );
  }

  @override
  void dispose() {
    _salaryController.dispose();
    super.dispose();
  }

  FreeAgentEntry get _entry =>
      widget.controller.career!.freeAgentPool.byId(widget.freeAgentId)!;

  int get _salary => _category == RosterCategory.twoWay
      ? FinancialRules.twoWaySalary
      : (int.tryParse(_salaryController.text.trim()) ?? 0);

  List<int> get _schedule => _category == RosterCategory.twoWay
      ? FinancialRules.twoWaySchedule(_durationYears)
      : FinancialRules.standardSchedule(_salary, _durationYears);

  int get _maxDuration => FinancialRules.maxDurationForCategory(_category);

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final career = widget.controller.career;
      if (career == null ||
          career.freeAgentPool.byId(widget.freeAgentId) == null) {
        return const Scaffold(
          body: Center(child: Text('Free agent is no longer available')),
        );
      }
      final team = career.userTeam;
      final view = _entry.toPublicView();
      final valuation = _market.estimate(view);
      final finances = career.finances;
      final teamId = career.userFranchiseId;
      final capPayroll = finances.capPayrollFor(teamId, career.currentYear);
      final cashPayroll = finances.cashPayrollFor(teamId, career.currentYear);
      final capRoom = FinancialRules.salaryCap - capPayroll;
      final proposedCap = _category == RosterCategory.standard
          ? capPayroll + _salary
          : capPayroll;
      final proposedCash = cashPayroll + _salary;
      final projectedCash =
          finances.projectedEndOfSeasonCash(teamId, career.currentYear) -
          _salary;
      final remaining = career.freeAgentOffers.remainingAttempts(
        teamId: teamId,
        playerId: widget.freeAgentId,
        seasonYear: career.currentYear,
      );

      return Scaffold(
        key: const ValueKey('free-agent-offer-screen'),
        appBar: AppBar(title: Text('Offer: ${view.fullName}')),
        body: ListView(
          key: const ValueKey('free-agent-offer-scroll'),
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${view.fullName} • ${view.position.shortName} • '
                      'Age ${view.age} • OVR ${view.overallRating}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Expected role: ${valuation.expectedRole.displayName} • '
                      'Preferred duration: '
                      '${valuation.preferredDurationYears} years',
                    ),
                    Text(
                      'Estimated market: '
                      '${valuation.estimatedAnnualSalary} CU/year. '
                      'This is guidance, not a guaranteed acceptance.',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text('Contract category', style: _sectionStyle(context)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  key: const ValueKey('offer-category-standard'),
                  label: const Text('Standard'),
                  selected: _category == RosterCategory.standard,
                  onSelected: (_) => _setCategory(RosterCategory.standard),
                ),
                ChoiceChip(
                  key: const ValueKey('offer-category-twoWay'),
                  label: const Text('Two-way'),
                  selected: _category == RosterCategory.twoWay,
                  onSelected: (_) => _setCategory(RosterCategory.twoWay),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Duration', style: _sectionStyle(context)),
            DropdownButton<int>(
              key: const ValueKey('offer-duration'),
              value: _durationYears,
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _durationYears = value;
                  if (_category == RosterCategory.standard) {
                    final maxSalary =
                        FreeAgentMarketValueService.maxYearOneForDuration(
                          value,
                        );
                    final current = int.tryParse(_salaryController.text) ?? 0;
                    _salaryController.text = current
                        .clamp(FinancialRules.minimumSalary, maxSalary)
                        .toString();
                  }
                });
              },
              items: [
                for (var year = 1; year <= _maxDuration; year++)
                  DropdownMenuItem(value: year, child: Text('$year years')),
              ],
            ),
            const SizedBox(height: 12),
            Text('First-year salary (CU)', style: _sectionStyle(context)),
            if (_category == RosterCategory.twoWay)
              const Text('Two-way salary is fixed at 250 CU.')
            else
              TextField(
                key: const ValueKey('offer-salary'),
                controller: _salaryController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: '400–8000',
                ),
                onChanged: (_) => setState(() {}),
              ),
            const SizedBox(height: 12),
            _PreviewRow(
              label: 'Annual schedule',
              value: _schedule.map((salary) => '$salary').join(' / '),
            ),
            _PreviewRow(label: 'Standard cap room', value: '$capRoom CU'),
            _PreviewRow(
              label: 'Proposed cap payroll',
              value: '$proposedCap CU',
            ),
            _PreviewRow(
              label: 'Proposed cash payroll',
              value: '$proposedCash CU',
            ),
            _PreviewRow(
              label: 'Projected season-end cash',
              value: '$projectedCash CU',
            ),
            _PreviewRow(
              label: 'Roster',
              value:
                  '${team.roster.standardCount}/'
                  '${RosterRules.maxOffseasonStandard} standard • '
                  '${team.roster.twoWayCount}/'
                  '${RosterRules.maxOffseasonTwoWay} two-way • '
                  '${team.roster.totalContractedCount}/'
                  '${RosterRules.maxOffseasonTotal} total',
            ),
            _PreviewRow(
              label: 'Formal offers remaining',
              value: '$remaining',
              key: const ValueKey('offer-attempts'),
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const ValueKey('offer-submit'),
              onPressed: remaining == 0 || _submitting ? null : _confirmOffer,
              child: Text(
                remaining == 0 ? 'No Offers Remaining' : 'Make Offer',
              ),
            ),
          ],
        ),
      );
    },
  );

  void _setCategory(RosterCategory category) {
    setState(() {
      _category = category;
      if (_durationYears > FinancialRules.maxDurationForCategory(category)) {
        _durationYears = FinancialRules.maxDurationForCategory(category);
      }
      if (category == RosterCategory.twoWay) {
        _salaryController.text = FinancialRules.twoWaySalary.toString();
      } else {
        final maxSalary = FreeAgentMarketValueService.maxYearOneForDuration(
          _durationYears,
        );
        final current = int.tryParse(_salaryController.text) ?? 0;
        _salaryController.text = (current.clamp(
          FinancialRules.minimumSalary,
          maxSalary,
        )).toString();
      }
    });
  }

  Future<void> _confirmOffer() async {
    final career = widget.controller.career!;
    final view = _entry.toPublicView();
    final schedule = _schedule;
    final capRoom =
        FinancialRules.salaryCap -
        career.finances.capPayrollFor(
          career.userFranchiseId,
          career.currentYear,
        );
    final projected =
        career.finances.projectedEndOfSeasonCash(
          career.userFranchiseId,
          career.currentYear,
        ) -
        schedule.first;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Contract Offer'),
        content: SingleChildScrollView(
          child: Text(
            'Player: ${view.fullName}\n'
            'Category: ${_category == RosterCategory.twoWay ? 'Two-way' : 'Standard'}\n'
            'Duration: $_durationYears year(s)\n'
            'Schedule: ${schedule.map((salary) => '$salary CU').join(' / ')}\n\n'
            'Current cap room: $capRoom CU\n'
            'Projected season-end cash: $projected CU\n'
            'Formal attempts remaining: '
            '${career.freeAgentOffers.remainingAttempts(teamId: career.userFranchiseId, playerId: widget.freeAgentId, seasonYear: career.currentYear)}',
          ),
        ),
        actions: [
          TextButton(
            key: const ValueKey('offer-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('offer-confirm-submit'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Submit Offer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _submitting = true);
    try {
      final result = await widget.controller.submitFreeAgentOffer(
        freeAgentId: widget.freeAgentId,
        category: _category,
        durationYears: _durationYears,
        agreedFirstYearSalary: _salary,
      );
      if (!mounted) return;
      await _showResult(result);
      if (result.status == FreeAgentOfferSubmissionStatus.accepted && mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Offer not submitted: $error')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _showResult(FreeAgentOfferSubmissionResult result) {
    final title = switch (result.status) {
      FreeAgentOfferSubmissionStatus.accepted => 'Offer Accepted',
      FreeAgentOfferSubmissionStatus.rejected => 'Offer Rejected',
      FreeAgentOfferSubmissionStatus.invalidTerms => 'Invalid Offer',
      FreeAgentOfferSubmissionStatus.financiallyIllegal =>
        'Offer Not Financially Legal',
    };
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(
          '${result.decision.explanation}\n\n'
          'Formal offers remaining: ${result.remainingAttempts}',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  TextStyle? _sectionStyle(BuildContext context) =>
      Theme.of(context).textTheme.titleSmall;
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(label)),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/providers.dart';
import '../domain/insights.dart';

class InsightsUiState {
  const InsightsUiState({required this.months, this.insights, this.exporting = false});
  final int months;
  final Insights? insights;
  final bool exporting;

  InsightsUiState copyWith({int? months, Insights? insights, bool? exporting}) => InsightsUiState(
    months: months ?? this.months,
    insights: insights ?? this.insights,
    exporting: exporting ?? this.exporting,
  );
}

class _PeriodNotifier extends Notifier<int> {
  @override
  int build() => 6;
  void set(int months) => state = months;
}

final _periodProvider = NotifierProvider<_PeriodNotifier, int>(_PeriodNotifier.new);

/// Presenter for Insights (FR-INS-01..03).
class InsightsPresenter extends Notifier<InsightsUiState> {
  @override
  InsightsUiState build() {
    final months = ref.watch(_periodProvider);
    final receipts = ref.watch(householdReceiptsProvider).value;
    final currency = ref.watch(settingsProvider.select((s) => s.value?.currency ?? 'PKR'));
    if (receipts == null) return InsightsUiState(months: months);
    return InsightsUiState(
      months: months,
      insights: ComputeInsights.compute(receipts, currency: currency, months: months, now: ref.read(clockProvider)()),
    );
  }

  void setPeriod(int months) => ref.read(_periodProvider.notifier).set(months);

  /// Returns an error message, or null on success.
  Future<String?> exportCsv() async {
    final receipts = ref.read(householdReceiptsProvider).value ?? const [];
    if (receipts.isEmpty) return 'There is nothing to export yet.';
    state = state.copyWith(exporting: true);
    try {
      final csv = ReceiptsCsv.build(receipts);
      await ref
          .read(fileExporterProvider)
          .share(
            bytes: Uint8List.fromList(utf8.encode(csv)),
            fileName: 'keepr-receipts.csv',
            mimeType: 'text/csv',
            subject: 'Keepr receipts export',
          );
      return null;
    } catch (_) {
      return 'Export failed. Please try again.';
    } finally {
      if (ref.mounted) state = state.copyWith(exporting: false);
    }
  }
}

final insightsPresenterProvider = NotifierProvider<InsightsPresenter, InsightsUiState>(InsightsPresenter.new);

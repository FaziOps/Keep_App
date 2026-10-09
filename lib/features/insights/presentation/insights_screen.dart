import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/domain/money.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/common.dart';
import '../../receipts/presentation/widgets/receipt_visuals.dart';
import '../domain/insights.dart';
import 'insights_presenter.dart';

class InsightsScreen extends ConsumerWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(insightsPresenterProvider);
    final presenter = ref.read(insightsPresenterProvider.notifier);
    final insights = state.insights;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Insights'),
        actions: [
          IconButton(
            tooltip: 'Export CSV',
            onPressed: state.exporting
                ? null
                : () async {
                    final error = await presenter.exportCsv();
                    if (error != null && context.mounted) showMessage(context, error, error: true);
                  },
            icon: const Icon(Icons.file_download_outlined),
          ),
        ],
      ),
      body: insights == null
          ? const Center(child: CircularProgressIndicator())
          : insights.isEmpty
          ? const EmptyState(
              icon: Icons.insights_rounded,
              title: 'No spending yet',
              message: 'Confirmed receipts show up here as monthly totals and categories.',
            )
          : ContentWidth(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 120),
                children: [
                  SegmentedButton<int>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: 3, label: Text('3 months')),
                      ButtonSegment(value: 6, label: Text('6 months')),
                      ButtonSegment(value: 12, label: Text('12 months')),
                    ],
                    selected: {state.months},
                    onSelectionChanged: (s) => presenter.setPeriod(s.first),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _Metric(
                          label: 'Spent',
                          value: formatMoney(insights.totalSpent, compact: true),
                          icon: Icons.payments_rounded,
                          color: KeeprColors.brand,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _Metric(
                          label: 'Protected value',
                          value: formatMoney(insights.protectedValue, compact: true),
                          icon: Icons.verified_user_rounded,
                          color: KeeprColors.success,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _Metric(
                          label: 'Active warranties',
                          value: '${insights.activeWarranties}',
                          icon: Icons.shield_rounded,
                          color: KeeprColors.sky,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _Metric(
                          label: 'Expiring soon',
                          value: '${insights.expiringSoon}',
                          icon: Icons.timelapse_rounded,
                          color: KeeprColors.amber,
                        ),
                      ),
                    ],
                  ),
                  const SectionHeader('Monthly spending'),
                  SurfaceCard(
                    padding: const EdgeInsets.fromLTRB(12, 20, 16, 12),
                    child: SizedBox(height: 220, child: _MonthlyChart(insights: insights)),
                  ),
                  if (insights.byCategory.isNotEmpty) ...[
                    const SectionHeader('By category'),
                    SurfaceCard(child: _CategoryBreakdown(insights: insights)),
                  ],
                  if (insights.otherCurrencyCount > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        '${insights.otherCurrencyCount} receipts in other currencies are not included in totals.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, required this.icon, required this.color});
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => SurfaceCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(height: 12),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value, style: Theme.of(context).textTheme.titleLarge),
        ),
        const SizedBox(height: 2),
        Text(label, style: Theme.of(context).textTheme.labelMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
      ],
    ),
  );
}

class _MonthlyChart extends StatelessWidget {
  const _MonthlyChart({required this.insights});
  final Insights insights;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final values = insights.monthly.map((m) => m.total.major).toList();
    final maxY = values.fold<double>(0, (a, b) => a > b ? a : b);
    final top = maxY == 0 ? 1.0 : maxY * 1.2;
    final labelStyle = Theme.of(context).textTheme.labelSmall;

    return BarChart(
      BarChartData(
        maxY: top,
        alignment: BarChartAlignment.spaceAround,
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          drawVerticalLine: false,
          horizontalInterval: top / 4,
          getDrawingHorizontalLine: (_) => FlLine(color: scheme.outlineVariant, strokeWidth: 1, dashArray: [4, 4]),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => scheme.inverseSurface,
            getTooltipItem: (group, _, rod, _) => BarTooltipItem(
              formatMoney(Money.fromMajor(rod.toY, insights.currency)),
              TextStyle(color: scheme.onInverseSurface, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              interval: top / 4,
              getTitlesWidget: (value, meta) => SideTitleWidget(
                meta: meta,
                child: Text(
                  formatMoney(
                    Money.fromMajor(value, insights.currency),
                    compact: true,
                  ).replaceAll(RegExp(r'^\D+\s?'), ''),
                  style: labelStyle,
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) => SideTitleWidget(
                meta: meta,
                child: Text(formatMonth(insights.monthly[value.toInt()].month), style: labelStyle),
              ),
            ),
          ),
        ),
        barGroups: [
          for (final (i, v) in values.indexed)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: v,
                  width: insights.monthly.length > 6 ? 14 : 24,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                  gradient: const LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [KeeprColors.brand, KeeprColors.brandBright],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _CategoryBreakdown extends StatelessWidget {
  const _CategoryBreakdown({required this.insights});
  final Insights insights;

  @override
  Widget build(BuildContext context) {
    final total = insights.totalSpent.major;
    final entries = insights.byCategory.entries.toList();
    return Column(
      children: [
        SizedBox(
          height: 180,
          child: PieChart(
            PieChartData(
              centerSpaceRadius: 52,
              sectionsSpace: 3,
              sections: [
                for (final e in entries)
                  PieChartSectionData(
                    value: e.value.major,
                    color: CategoryStyle.of(e.key).color,
                    radius: 34,
                    showTitle: false,
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        for (final e in entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                CategoryAvatar(e.key, size: 34),
                const SizedBox(width: 12),
                Expanded(child: Text(e.key.label, style: Theme.of(context).textTheme.titleSmall)),
                Text(
                  total == 0 ? '0%' : '${(e.value.major / total * 100).round()}%',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 96,
                  child: Text(
                    formatMoney(e.value),
                    textAlign: TextAlign.end,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

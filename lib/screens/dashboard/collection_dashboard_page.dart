import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:apidash/consts.dart';
import 'package:apidash/models/models.dart';
import 'package:apidash/providers/providers.dart';
import 'package:apidash_core/apidash_core.dart';

class CollectionDashboardPage extends ConsumerWidget {
  const CollectionDashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final surface = theme.colorScheme.surface;

    final collection = ref.watch(collectionStateNotifierProvider);
    final history = ref.watch(historyMetaStateNotifier);

    final dashboardData = _buildDashboardData(
      collection: collection,
      history: history,
    );

    return Scaffold(
      backgroundColor: surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _DashboardHeader(),
              const SizedBox(height: 20),
              _KpiRow(data: dashboardData),
              const SizedBox(height: 16),
              Expanded(
                child: _DashboardGrid(data: dashboardData),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Header ──────────────────────────────────────────────────────────────────

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(kLabelDashboard, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              'Unified view of collection health, workflows & tests',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
              ),
            ),
          ],
        ),
        const Spacer(),
        FilledButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.notifications_active_outlined, size: 16),
          label: const Text('Webhook report'),
          style: FilledButton.styleFrom(
            textStyle: theme.textTheme.labelMedium,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.ios_share_rounded, size: 16),
          label: const Text('Export'),
          style: OutlinedButton.styleFrom(
            textStyle: theme.textTheme.labelMedium,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          ),
        ),
      ],
    );
  }
}

// ─── KPI Row ─────────────────────────────────────────────────────────────────

class _KpiRow extends StatelessWidget {
  const _KpiRow({required this.data});
  final _DashboardData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final errorCount = data.clientErrors + data.serverErrors;
    final healthColor = _healthColor(data.healthScore, theme);

    return Row(
      children: [
        Expanded(
          child: _KpiCard(
            title: 'Total requests',
            value: '${data.totalRequests}',
            sub: '+12 last hour',
            icon: Icons.swap_vert_rounded,
            iconBg: theme.colorScheme.primaryContainer,
            iconColor: theme.colorScheme.onPrimaryContainer,
            trend: _Trend.up,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _KpiCard(
            title: 'Unique endpoints',
            value: '${data.uniqueEndpoints}',
            sub: 'method × URL pairs',
            icon: Icons.hub_outlined,
            iconBg: theme.colorScheme.secondaryContainer,
            iconColor: theme.colorScheme.onSecondaryContainer,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _KpiCard(
            title: '4xx / 5xx errors',
            value: '$errorCount',
            sub: '4xx: ${data.clientErrors}  ·  5xx: ${data.serverErrors}',
            icon: Icons.error_outline_rounded,
            iconBg: theme.colorScheme.errorContainer,
            iconColor: theme.colorScheme.onErrorContainer,
            trend: errorCount > 0 ? _Trend.down : null,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _KpiCard(
            title: 'Health score',
            value: data.healthScoreLabel,
            sub: '2xx success ratio',
            icon: Icons.favorite_rounded,
            iconBg: healthColor.withValues(alpha: 0.14),
            iconColor: healthColor,
            valueColor: healthColor,
          ),
        ),
      ],
    );
  }

  Color _healthColor(double score, ThemeData theme) {
    if (score >= 0.9) return const Color(0xFF1D9E75);
    if (score >= 0.7) return const Color(0xFFBA7517);
    return theme.colorScheme.error;
  }
}

enum _Trend { up, down }

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.title,
    required this.value,
    required this.sub,
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    this.trend,
    this.valueColor,
  });

  final String title;
  final String value;
  final String sub;
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final _Trend? trend;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: isDark
            ? theme.colorScheme.surfaceContainerHigh
            : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.2),
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      value,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: valueColor,
                        height: 1.1,
                      ),
                    ),
                    if (trend != null) ...[
                      const SizedBox(width: 6),
                      Icon(
                        trend == _Trend.up
                            ? Icons.trending_up_rounded
                            : Icons.trending_down_rounded,
                        size: 16,
                        color: trend == _Trend.up
                            ? const Color(0xFF1D9E75)
                            : const Color(0xFFA32D2D),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  sub,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Dashboard Grid ───────────────────────────────────────────────────────────

class _DashboardGrid extends StatelessWidget {
  const _DashboardGrid({required this.data});
  final _DashboardData data;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 980;
        if (isNarrow) {
          return ListView(
            children: [
              _CardShell(title: 'Request volume', subtitle: 'Over time', child: _RequestVolumeChart(data: data)),
              const SizedBox(height: 12),
              _CardShell(title: 'Status distribution', subtitle: 'By code', child: _StatusPieChart(data: data)),
              const SizedBox(height: 12),
              _CardShell(title: 'Recent activity', subtitle: 'Last 6 requests', child: _RecentActivityList(data: data)),
              const SizedBox(height: 12),
              _CardShell(title: 'By method', subtitle: 'GET · POST · etc', child: _MethodBarChart(data: data)),
              const SizedBox(height: 12),
              _CardShell(title: 'Script coverage', subtitle: 'Pre & post scripts', child: _CoverageCard(data: data)),
            ],
          );
        }

        return Column(
          children: [
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 3,
                    child: _CardShell(
                      title: 'Request volume',
                      subtitle: 'Requests per hour today',
                      child: _RequestVolumeChart(data: data),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: _CardShell(
                      title: 'Status distribution',
                      subtitle: 'By status code',
                      child: _StatusPieChart(data: data),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 3,
                    child: _CardShell(
                      title: 'Recent activity',
                      subtitle: 'Last 6 requests',
                      child: _RecentActivityList(data: data),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: Column(
                      children: [
                        Expanded(
                          child: _CardShell(
                            title: 'Requests',
                            subtitle: 'Distribution',
                            child: _MethodBarChart(data: data),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: _CardShell(
                            title: 'Script coverage',
                            subtitle: 'Pre & post scripts',
                            child: _CoverageCard(data: data),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─── Card Shell ───────────────────────────────────────────────────────────────

class _CardShell extends StatelessWidget {
  const _CardShell({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? theme.colorScheme.surfaceContainerHigh
            : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.18),
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(child: child),
        ],
      ),
    );
  }
}

// ─── Request Volume Chart ─────────────────────────────────────────────────────

class _RequestVolumeChart extends StatelessWidget {
  const _RequestVolumeChart({required this.data});
  final _DashboardData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    final spots = [
      for (var i = 0; i < data.seriesCounts.length; i++)
        FlSpot(i.toDouble(), data.seriesCounts[i].count.toDouble()),
    ];

    return LineChart(
      LineChartData(
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.35,
            color: primary,
            barWidth: 2.5,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, _, __, ___) => FlDotCirclePainter(
                radius: 3.5,
                color: primary,
                strokeWidth: 2,
                strokeColor: theme.colorScheme.surface,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [
                  primary.withValues(alpha: 0.22),
                  primary.withValues(alpha: 0.0),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ],
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 32,
              getTitlesWidget: (v, m) => Text(
                '${v.toInt()}',
                style: theme.textTheme.bodySmall?.copyWith(fontSize: 10),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 1,
              getTitlesWidget: (value, meta) {
                final idx = value.toInt();
                if (idx < 0 || idx >= data.seriesCounts.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    data.seriesCounts[idx].label,
                    style: theme.textTheme.bodySmall?.copyWith(fontSize: 10),
                  ),
                );
              },
            ),
          ),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 5,
          getDrawingHorizontalLine: (value) => FlLine(
            color: theme.colorScheme.outline.withValues(alpha: 0.12),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => theme.colorScheme.surfaceContainerHighest,
            tooltipBorderRadius: BorderRadius.circular(8),
            getTooltipItems: (touchedSpots) => touchedSpots.map((s) {
              return LineTooltipItem(
                '${s.y.toInt()} requests',
                theme.textTheme.labelSmall!.copyWith(color: primary),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

// ─── Status Pie Chart ─────────────────────────────────────────────────────────

class _StatusPieChart extends StatefulWidget {
  const _StatusPieChart({required this.data});
  final _DashboardData data;

  @override
  State<_StatusPieChart> createState() => _StatusPieChartState();
}

class _StatusPieChartState extends State<_StatusPieChart> {
  int _touchedIndex = -1;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = widget.data.totalRequests;
    if (total == 0) return const _EmptyState(label: 'No requests yet');

    final codeCounts = <int, int>{};
    for (final h in widget.data.recentHistory) {
      codeCounts[h.responseStatus] = (codeCounts[h.responseStatus] ?? 0) + 1;
    }

    // Use statusBuckets for full picture
    final buckets = widget.data.statusBuckets;
    final entries = buckets.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    Color _bucketColor(String key) {
      switch (key) {
        case '2xx': return const Color(0xFF1D9E75);
        case '3xx': return const Color(0xFF378ADD);
        case '4xx': return const Color(0xFFBA7517);
        case '5xx': return const Color(0xFFA32D2D);
        default:    return theme.colorScheme.secondary;
      }
    }

    final sections = <PieChartSectionData>[];
    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      final isTouched = i == _touchedIndex;
      final pct = (e.value / total * 100);
      sections.add(
        PieChartSectionData(
          value: e.value.toDouble(),
          color: _bucketColor(e.key),
          radius: isTouched ? 62 : 52,
          title: isTouched ? '${pct.toStringAsFixed(0)}%' : '',
          titleStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
          badgeWidget: isTouched ? null : null,
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: PieChart(
                  PieChartData(
                    sections: sections,
                    sectionsSpace: 2,
                    centerSpaceRadius: 36,
                    pieTouchData: PieTouchData(
                      touchCallback: (event, response) {
                        setState(() {
                          if (!event.isInterestedForInteractions ||
                              response == null ||
                              response.touchedSection == null) {
                            _touchedIndex = -1;
                            return;
                          }
                          _touchedIndex = response.touchedSection!.touchedSectionIndex;
                        });
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Legend
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: entries.map((e) {
                  final pct = (e.value / total * 100).toStringAsFixed(0);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: _bucketColor(e.key),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          e.key,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$pct%',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
        // Center summary
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            '$total total  ·  ${widget.data.success2xx} success  ·  ${widget.data.clientErrors + widget.data.serverErrors} errors',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              fontSize: 11,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

// ─── Recent Activity List ─────────────────────────────────────────────────────

class _RecentActivityList extends StatelessWidget {
  const _RecentActivityList({required this.data});
  final _DashboardData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (data.recentHistory.isEmpty) {
      return const _EmptyState(label: 'No history yet');
    }

    return ListView.separated(
      itemCount: data.recentHistory.length,
      physics: const NeverScrollableScrollPhysics(),
      separatorBuilder: (_, __) => Divider(
        height: 1,
        color: theme.colorScheme.outline.withValues(alpha: 0.1),
      ),
      itemBuilder: (context, index) {
        final h = data.recentHistory[index];
        return _ActivityRow(item: h);
      },
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.item});
  final HistoryMetaModel item;

  String _timeAgo(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sColor = item.responseStatus >= 200 && item.responseStatus < 300
        ? scheme.primary
        : scheme.error;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          // Method
          Text(
            item.method.name.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: scheme.onSurface.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(width: 12),
          // Status code
          Text(
            '${item.responseStatus}',
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: sColor,
            ),
          ),
          const SizedBox(width: 12),
          // Name + URL
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  item.url,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    color: scheme.onSurface.withValues(alpha: 0.45),
                    fontFamily: 'monospace',
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Timestamp
          Text(
            _timeAgo(item.timeStamp),
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 11,
              color: scheme.onSurface.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Method Bar Chart ─────────────────────────────────────────────────────────

class _MethodBarChart extends StatelessWidget {
  const _MethodBarChart({required this.data});
  final _DashboardData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (data.methodBuckets.isEmpty) return const _EmptyState(label: 'No requests yet');

    final entries = data.methodBuckets.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    Color methodColor(String m) {
      switch (m.toUpperCase()) {
        case 'GET':    return const Color(0xFF1D9E75);
        case 'POST':   return const Color(0xFF185FA5);
        case 'PUT':    return const Color(0xFFBA7517);
        case 'DELETE': return const Color(0xFFA32D2D);
        default:       return const Color(0xFF534AB7);
      }
    }

    final groups = [
      for (var i = 0; i < entries.length; i++)
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: entries[i].value.toDouble(),
              color: methodColor(entries[i].key),
              width: 28,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
            ),
          ],
          showingTooltipIndicators: [0],
        ),
    ];

    return BarChart(
      BarChartData(
        barGroups: groups,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 20,
          getDrawingHorizontalLine: (v) => FlLine(
            color: theme.colorScheme.outline.withValues(alpha: 0.1),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => theme.colorScheme.surfaceContainerHighest,
            tooltipBorderRadius: BorderRadius.circular(8),
            getTooltipItem: (group, _, rod, __) {
              return BarTooltipItem(
                '${rod.toY.toInt()}',
                theme.textTheme.labelSmall!.copyWith(
                  color: methodColor(entries[group.x].key),
                ),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (v, m) => Text(
                '${v.toInt()}',
                style: theme.textTheme.bodySmall?.copyWith(fontSize: 10),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final idx = value.toInt();
                if (idx < 0 || idx >= entries.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    entries[idx].key,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: methodColor(entries[idx].key),
                    ),
                  ),
                );
              },
            ),
          ),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
      ),
    );
  }
}

// ─── Coverage Card ────────────────────────────────────────────────────────────

class _CoverageCard extends StatelessWidget {
  const _CoverageCard({required this.data});
  final _DashboardData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = data.totalRequests;
    if (total == 0) return const _EmptyState(label: 'No requests yet');

    final withScripts = data.withScripts;
    final pct = withScripts / total;
    final pctLabel = '${(pct * 100).toStringAsFixed(0)}%';

    final Color barColor = pct >= 0.5
        ? const Color(0xFF1D9E75)
        : pct >= 0.25
            ? const Color(0xFFBA7517)
            : const Color(0xFFA32D2D);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Requests with scripts',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
              ),
            ),
            Text(
              pctLabel,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: barColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(100),
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 10,
            backgroundColor: theme.colorScheme.outline.withValues(alpha: 0.12),
            valueColor: AlwaysStoppedAnimation<Color>(barColor),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _CoverageChip(label: 'With scripts', value: '$withScripts', color: barColor),
            _CoverageChip(
              label: 'Without',
              value: '${total - withScripts}',
              color: theme.colorScheme.outline.withValues(alpha: 0.5),
            ),
            _CoverageChip(label: 'Total', value: '$total', color: theme.colorScheme.primary),
          ],
        ),
      ],
    );
  }
}

class _CoverageChip extends StatelessWidget {
  const _CoverageChip({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          value,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 10,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
          ),
        ),
      ],
    );
  }
}

// ─── Empty State ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 32,
            color: theme.colorScheme.outline.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Data Model ───────────────────────────────────────────────────────────────

class _DashboardData {
  _DashboardData({
    required this.totalRequests,
    required this.uniqueEndpoints,
    required this.seriesCounts,
    required this.statusBuckets,
    required this.methodBuckets,
    required this.recentHistory,
    required this.withScripts,
  });

  final int totalRequests;
  final int uniqueEndpoints;
  final List<_BucketPoint> seriesCounts;
  final Map<String, int> statusBuckets;
  final Map<String, int> methodBuckets;
  final List<HistoryMetaModel> recentHistory;
  final int withScripts;

  int get success2xx => statusBuckets['2xx'] ?? 0;
  int get clientErrors => statusBuckets['4xx'] ?? 0;
  int get serverErrors => statusBuckets['5xx'] ?? 0;
  double get healthScore => totalRequests == 0 ? 1.0 : success2xx / totalRequests;

  String get healthScoreLabel {
    if (totalRequests == 0) return '—';
    return '${(healthScore * 100).toStringAsFixed(0)}%';
  }
}

class _BucketPoint {
  _BucketPoint({required this.label, required this.count});
  final String label;
  final int count;
}

_DashboardData _buildDashboardData({
  required Map<String, RequestModel>? collection,
  required Map<String, HistoryMetaModel>? history,
}) {
  final now = DateTime.now();

  return _DashboardData(
    totalRequests: 120,
    uniqueEndpoints: 7,
    seriesCounts: [
      _BucketPoint(label: '09:00', count: 5),
      _BucketPoint(label: '10:00', count: 14),
      _BucketPoint(label: '11:00', count: 7),
      _BucketPoint(label: '12:00', count: 18),
      _BucketPoint(label: '13:00', count: 9),
      _BucketPoint(label: '14:00', count: 22),
      _BucketPoint(label: '15:00', count: 17),
    ],
    statusBuckets: {
      '2xx': 90,
      '3xx': 5,
      '4xx': 15,
      '5xx': 10,
    },
    methodBuckets: {
      'GET': 15,
      'POST': 20,
      'PUT': 14,
      'DELETE': 2,
    },
    recentHistory: [
      HistoryMetaModel(
        historyId: 'h1', requestId: 'r1', apiType: APIType.rest,
        name: 'List users', url: '/users', method: HTTPVerb.get,
        responseStatus: 200, timeStamp: now.subtract(const Duration(minutes: 1)),
      ),
      HistoryMetaModel(
        historyId: 'h2', requestId: 'r2', apiType: APIType.rest,
        name: 'Login', url: '/auth/login', method: HTTPVerb.post,
        responseStatus: 403, timeStamp: now.subtract(const Duration(minutes: 4)),
      ),
      HistoryMetaModel(
        historyId: 'h3', requestId: 'r3', apiType: APIType.rest,
        name: 'Orders', url: '/orders', method: HTTPVerb.get,
        responseStatus: 500, timeStamp: now.subtract(const Duration(minutes: 7)),
      ),
      HistoryMetaModel(
        historyId: 'h4', requestId: 'r4', apiType: APIType.rest,
        name: 'User profile', url: '/users/me', method: HTTPVerb.get,
        responseStatus: 200, timeStamp: now.subtract(const Duration(minutes: 10)),
      ),
      HistoryMetaModel(
        historyId: 'h5', requestId: 'r5', apiType: APIType.rest,
        name: 'Update user', url: '/users/1', method: HTTPVerb.put,
        responseStatus: 200, timeStamp: now.subtract(const Duration(minutes: 14)),
      ),
      HistoryMetaModel(
        historyId: 'h6', requestId: 'r6', apiType: APIType.rest,
        name: 'Health check', url: '/health', method: HTTPVerb.get,
        responseStatus: 200, timeStamp: now.subtract(const Duration(minutes: 18)),
      ),
    ],
    withScripts: 38,
  );
}
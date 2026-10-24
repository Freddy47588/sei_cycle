import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../theme/app_theme.dart';
import '../models/dashboard_filter.dart';
import '../models/productivity_point.dart';

class ProductivityChart extends StatelessWidget {
  const ProductivityChart({
    required this.series,
    required this.filter,
    super.key,
  });
  final ProductivitySeries series;
  final DashboardFilter filter;
  @override
  Widget build(BuildContext context) {
    final points =
        series.points
            .where(
              (p) =>
                  p.value.isFinite &&
                  p.value >= 0 &&
                  p.value <= 1e15 &&
                  filter.contains(p.date),
            )
            .toList()
          ..sort((a, b) => a.date.compareTo(b.date));
    if (points.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('Belum ada data produktivitas pada periode ini.'),
      );
    }
    final summaryValue = series.additive
        ? points.fold<double>(0, (total, p) => total + p.value)
        : points.last.value;
    int day(DateTime date) => DateTime.utc(date.year, date.month, date.day)
        .difference(
          DateTime.utc(filter.start.year, filter.start.month, filter.start.day),
        )
        .inDays;
    final spots = points
        .map((p) => FlSpot(day(p.date).toDouble(), p.value))
        .toList();
    final minX = spots.first.x;
    final maxX = math.max(minX + 1, spots.last.x);
    final maxY = math.max(
      1.0,
      points.map((p) => p.value).reduce(math.max) * 1.15,
    );
    String dateLabel(double x) => DateFormat('d/M').format(
      DateTime(
        filter.start.year,
        filter.start.month,
        filter.start.day + x.round(),
      ),
    );
    String valueLabel(double y) =>
        NumberFormat.compact(locale: 'id_ID').format(y);
    String tooltip(double x, double y) =>
        '${dateLabel(x)}\n${NumberFormat.decimalPattern('id_ID').format(y)} ${series.unit}';
    const color = AppColors.primaryGreen;
    final segments = <List<FlSpot>>[];
    for (final spot in spots) {
      if (segments.isEmpty || spot.x - segments.last.last.x > 1) {
        segments.add([]);
      }
      segments.last.add(spot);
    }
    final scale = MediaQuery.textScalerOf(context).scale(1);
    Widget chart(double width) {
      // Bars occupy observed dates only. A long empty calendar must not squeeze
      // a handful of real observations into subpixel rods.
      final contentWidth = series.additive
          ? math.max(width, points.length * 32.0 + 64 * scale)
          : width;
      final plotWidth = math.max(1.0, contentWidth - 64 * scale);
      final labelWidth = 64 * scale;
      final labelXs = <double>[];
      final candidates = series.additive
          ? List.generate(points.length, (i) => i.toDouble())
          : spots.map((spot) => spot.x).toList();
      final axisMin = series.additive ? 0.0 : minX;
      final axisSpan = series.additive
          ? math.max(1, points.length - 1).toDouble()
          : maxX - minX;
      for (final x in candidates) {
        if (labelXs.isEmpty ||
            (x - labelXs.last) / axisSpan * plotWidth >= labelWidth) {
          labelXs.add(x);
        }
      }
      final titles = FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 48 * scale,
            interval: maxY / 4,
            getTitlesWidget: (v, meta) =>
                Text(valueLabel(v), style: const TextStyle(fontSize: 10)),
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 24 * scale + 8,
            interval: 1,
            getTitlesWidget: (v, meta) {
              if (!labelXs.any((x) => (x - v).abs() < 0.001)) {
                return const SizedBox.shrink();
              }
              return SideTitleWidget(
                meta: meta,
                space: 6,
                fitInside: SideTitleFitInsideData.fromTitleMeta(
                  meta,
                  enabled: true,
                ),
                child: Text(
                  dateLabel(series.additive ? spots[v.round()].x : v),
                  style: const TextStyle(fontSize: 10),
                ),
              );
            },
          ),
        ),
      );
      final rendered = SizedBox(
        width: contentWidth,
        height: 220 + 24 * (scale - 1),
        child: series.additive
            ? BarChart(
                BarChartData(
                  maxY: maxY,
                  minY: 0,
                  titlesData: titles,
                  borderData: FlBorderData(show: false),
                  alignment: BarChartAlignment.spaceAround,
                  gridData: const FlGridData(drawVerticalLine: false),
                  barGroups: [
                    for (var index = 0; index < spots.length; index++)
                      BarChartGroupData(
                        x: index,
                        barRods: [
                          BarChartRodData(
                            toY: spots[index].y,
                            color: color,
                            width: 14,
                          ),
                        ],
                      ),
                  ],
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      fitInsideHorizontally: true,
                      fitInsideVertically: true,
                      getTooltipItem: (group, index, rod, rodIndex) =>
                          BarTooltipItem(
                            tooltip(spots[group.x].x, rod.toY),
                            const TextStyle(color: Colors.white),
                          ),
                    ),
                  ),
                ),
                duration: Duration.zero,
              )
            : LineChart(
                LineChartData(
                  minX: axisMin,
                  maxX: maxX,
                  minY: 0,
                  maxY: maxY,
                  titlesData: titles,
                  borderData: FlBorderData(show: false),
                  gridData: const FlGridData(drawVerticalLine: false),
                  lineBarsData: [
                    for (final segment in segments)
                      LineChartBarData(
                        spots: segment,
                        color: color,
                        isCurved: false,
                        barWidth: 2,
                        dotData: const FlDotData(show: true),
                      ),
                  ],
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      fitInsideHorizontally: true,
                      fitInsideVertically: true,
                      getTooltipItems: (spots) => [
                        for (final spot in spots)
                          LineTooltipItem(
                            tooltip(spot.x, spot.y),
                            const TextStyle(color: Colors.white),
                          ),
                      ],
                    ),
                  ),
                ),
                duration: Duration.zero,
              ),
      );
      if (contentWidth <= width) return rendered;
      return Scrollbar(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: rendered,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(series.label, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        Text(
          '${series.additive ? 'Total tercatat' : 'Pengamatan terbaru'}: ${valueLabel(summaryValue)} ${series.unit}',
        ),
        Text(
          '${filter.label} · ${points.length} hari dengan data',
          style: const TextStyle(color: AppColors.textMuted),
        ),
        if (series.additive)
          const Text(
            'Batang berurutan menurut tanggal pengamatan. Geser untuk data padat.',
            style: TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) => chart(constraints.maxWidth),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            const Icon(Icons.circle, size: 10, color: color),
            Text(
              '${series.unit} · ${series.additive ? 'Batang per hari tercatat' : 'Garis pengamatan; jeda tetap kosong'}',
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ],
        ),
      ],
    );
  }
}

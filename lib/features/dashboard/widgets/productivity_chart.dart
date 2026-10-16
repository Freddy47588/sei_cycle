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
    final points = series.points
        .where(
          (p) =>
              p.value.isFinite &&
              p.value >= 0 &&
              p.value <= 1e15 &&
              filter.contains(p.date),
        )
        .toList();
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
    final maxX = math.max(
      1.0,
      day(
        DateTime(filter.end.year, filter.end.month, filter.end.day - 1),
      ).toDouble(),
    );
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
    final titles = FlTitlesData(
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 48,
          interval: maxY / 4,
          getTitlesWidget: (v, meta) =>
              Text(valueLabel(v), style: const TextStyle(fontSize: 10)),
        ),
      ),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 32,
          interval: math
              .max(
                1,
                (maxX / (MediaQuery.sizeOf(context).width < 400 ? 2 : 3))
                    .ceil(),
              )
              .toDouble(),
          getTitlesWidget: (v, meta) {
            if (v >
                day(
                  DateTime(
                    filter.end.year,
                    filter.end.month,
                    filter.end.day - 1,
                  ),
                )) {
              return const SizedBox.shrink();
            }
            return SideTitleWidget(
              meta: meta,
              space: 6,
              fitInside: SideTitleFitInsideData.fromTitleMeta(
                meta,
                enabled: true,
              ),
              child: Text(dateLabel(v), style: const TextStyle(fontSize: 10)),
            );
          },
        ),
      ),
    );
    const color = AppColors.primaryGreen;
    final segments = <List<FlSpot>>[];
    for (final spot in spots) {
      if (segments.isEmpty || spot.x - segments.last.last.x > 1) {
        segments.add([]);
      }
      segments.last.add(spot);
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
        const SizedBox(height: 16),
        SizedBox(
          height: 220,
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
                      for (var day = 0; day <= maxX; day++)
                        BarChartGroupData(
                          x: day,
                          barRods: [
                            for (final spot in spots.where(
                              (spot) => spot.x == day,
                            ))
                              BarChartRodData(
                                toY: spot.y,
                                color: color,
                                width: math.min(16, 160 / (maxX + 1)),
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
                              '${dateLabel(group.x.toDouble())}\n${valueLabel(rod.toY)} ${series.unit}',
                              const TextStyle(color: Colors.white),
                            ),
                      ),
                    ),
                  ),
                  duration: Duration.zero,
                )
              : LineChart(
                  LineChartData(
                    minX: 0,
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
                              '${dateLabel(spot.x)}\n${valueLabel(spot.y)} ${series.unit}',
                              const TextStyle(color: Colors.white),
                            ),
                        ],
                      ),
                    ),
                  ),
                  duration: Duration.zero,
                ),
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

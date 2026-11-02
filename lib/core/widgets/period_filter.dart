import 'package:flutter/material.dart';
import '../utils/formatters.dart';

/// End is exclusive in every service query.
DateTimeRange monthPeriod([DateTime? anchor]) {
  final now = anchor ?? DateTime.now();
  return DateTimeRange(
    start: DateTime(now.year, now.month),
    end: DateTime(now.year, now.month + 1),
  );
}

class PeriodFilter extends StatefulWidget {
  const PeriodFilter({required this.value, required this.onChanged, super.key});
  final DateTimeRange value;
  final ValueChanged<DateTimeRange> onChanged;
  @override
  State<PeriodFilter> createState() => _PeriodFilterState();
}

class _PeriodFilterState extends State<PeriodFilter> {
  String _selection = 'month';
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        initialValue: _selection,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Periode'),
        items: const [
          DropdownMenuItem(value: 'today', child: Text('Hari Ini')),
          DropdownMenuItem(value: 'week', child: Text('7 Hari Terakhir')),
          DropdownMenuItem(value: 'month', child: Text('Bulan Ini')),
          DropdownMenuItem(value: 'previous', child: Text('Bulan Sebelumnya')),
          DropdownMenuItem(value: 'custom', child: Text('Rentang Tanggal')),
        ],
        onChanged: (value) async {
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          DateTimeRange? period;
          if (value == 'custom') {
            final picked = await showDateRangePicker(
              context: context,
              firstDate: DateTime(2020),
              lastDate: DateTime(2100),
            );
            if (picked != null) {
              period = DateTimeRange(
                start: picked.start,
                end: DateTime(
                  picked.end.year,
                  picked.end.month,
                  picked.end.day + 1,
                ),
              );
            }
          } else {
            period = switch (value) {
              'today' => DateTimeRange(
                start: today,
                end: DateTime(now.year, now.month, now.day + 1),
              ),
              'week' => DateTimeRange(
                start: DateTime(now.year, now.month, now.day - 6),
                end: DateTime(now.year, now.month, now.day + 1),
              ),
              'previous' => monthPeriod(DateTime(now.year, now.month - 1)),
              _ => monthPeriod(now),
            };
          }
          if (period != null && mounted) {
            setState(() => _selection = value!);
            widget.onChanged(period);
          }
        },
      ),
      Text(
        '${shortDateFormat.format(widget.value.start)} – ${shortDateFormat.format(widget.value.end.subtract(const Duration(microseconds: 1)))}',
      ),
    ],
  );
}

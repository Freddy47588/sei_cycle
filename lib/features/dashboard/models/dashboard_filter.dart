import 'package:intl/intl.dart';

/// Local calendar boundaries: inclusive start, exclusive end.
class DashboardFilter {
  DashboardFilter({required this.start, required this.end}) {
    if (!start.isBefore(end) ||
        start.isUtc ||
        end.isUtc ||
        start != DateTime(start.year, start.month, start.day) ||
        end != DateTime(end.year, end.month, end.day)) {
      throw ArgumentError('Periode harus berupa hari kalender lokal.');
    }
  }

  factory DashboardFilter.days(int days, {DateTime? now}) {
    if (days < 1 || days > 366) throw ArgumentError('Rentang 1–366 hari.');
    final today = (now ?? DateTime.now()).toLocal();
    return DashboardFilter(
      start: DateTime(today.year, today.month, today.day - days + 1),
      end: DateTime(today.year, today.month, today.day + 1),
    );
  }

  final DateTime start, end;
  bool contains(DateTime date) => !date.isBefore(start) && date.isBefore(end);
  String get label {
    final last = DateTime(end.year, end.month, end.day - 1);
    final format = DateFormat('d MMM yyyy', 'id_ID');
    return '${format.format(start)} – ${format.format(last)}';
  }
}

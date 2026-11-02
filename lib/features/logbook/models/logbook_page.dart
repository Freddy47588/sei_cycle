import 'package:cloud_firestore/cloud_firestore.dart';
import 'logbook_entry.dart';

class LogbookFilter {
  const LogbookFilter({
    this.moduleId,
    this.batchId,
    this.start,
    this.endExclusive,
    this.newestFirst = true,
  });
  final String? moduleId;
  final String? batchId;
  final DateTime? start;
  final DateTime? endExclusive;
  final bool newestFirst;

  factory LogbookFilter.forPeriod({
    String? moduleId,
    required String period,
    required DateTime now,
    DateTime? customStart,
    DateTime? customEnd,
    bool newestFirst = true,
  }) {
    final today = DateTime(now.year, now.month, now.day);
    final start = switch (period) {
      'Hari ini' => today,
      '7 hari terakhir' => DateTime(now.year, now.month, now.day - 6),
      'Bulan ini' => DateTime(now.year, now.month),
      'Rentang tanggal' =>
        customStart == null
            ? null
            : DateTime(customStart.year, customStart.month, customStart.day),
      _ => null,
    };
    final end = period == 'Rentang tanggal' ? customEnd : now;
    return LogbookFilter(
      moduleId: moduleId,
      start: start,
      endExclusive: start == null || end == null
          ? null
          : DateTime(end.year, end.month, end.day + 1),
      newestFirst: newestFirst,
    );
  }
}

class LogbookPage {
  const LogbookPage({
    required this.entries,
    this.cursor,
    required this.hasMore,
  });
  final List<LogbookEntry> entries;
  final DocumentSnapshot<Map<String, dynamic>>? cursor;
  final bool hasMore;
}

class LogbookLinks {
  const LogbookLinks({this.inventory = const [], this.production = const []});
  final List<Map<String, dynamic>> inventory;
  final List<Map<String, dynamic>> production;
}

List<LogbookEntry> searchLoadedLogbooks(
  Iterable<LogbookEntry> entries,
  String search,
) {
  final query = search.trim().toLowerCase();
  return entries
      .where((e) => '${e.title} ${e.note}'.toLowerCase().contains(query))
      .toList();
}

List<LogbookEntry> mergeLogbookPages(
  List<LogbookEntry> current,
  List<LogbookEntry> next,
) => {
  for (final entry in [...current, ...next]) entry.id: entry,
}.values.toList();

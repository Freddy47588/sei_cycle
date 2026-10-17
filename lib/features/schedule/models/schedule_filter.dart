import 'schedule_item.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

enum ScheduleView { today, upcoming, overdue, done, all }

String scheduleViewLabel(ScheduleView view) => switch (view) {
  ScheduleView.today => 'Hari Ini',
  ScheduleView.upcoming => 'Mendatang',
  ScheduleView.overdue => 'Terlewat',
  ScheduleView.done => 'Selesai',
  ScheduleView.all => 'Semua Jadwal',
};

class ScheduleFilter {
  const ScheduleFilter({
    this.view = ScheduleView.today,
    this.date,
    this.batchId,
    this.moduleType,
  });
  final ScheduleView view;
  final DateTime? date;
  final String? batchId, moduleType;

  bool matches(ScheduleItem item, DateTime now) {
    if (item.isDeleted ||
        (batchId != null && item.batchId != batchId) ||
        (moduleType != null && item.moduleId != moduleType)) {
      return false;
    }
    if (view == ScheduleView.done && item.status != 'done') return false;
    if ({ScheduleView.upcoming, ScheduleView.overdue}.contains(view) &&
        item.status != 'pending') {
      return false;
    }
    if (view == ScheduleView.upcoming && item.scheduledAt.isBefore(now)) {
      return false;
    }
    if (view == ScheduleView.overdue && !item.scheduledAt.isBefore(now)) {
      return false;
    }
    if (date != null || view == ScheduleView.today) {
      final day = date ?? now;
      return item.scheduledAt.year == day.year &&
          item.scheduledAt.month == day.month &&
          item.scheduledAt.day == day.day;
    }
    return true;
  }

  Query<Map<String, dynamic>> apply(
    Query<Map<String, dynamic>> q,
    DateTime now,
  ) {
    q = q.where('isDeleted', isEqualTo: false);
    if (batchId != null) q = q.where('batchId', isEqualTo: batchId);
    if (moduleType != null) q = q.where('moduleType', isEqualTo: moduleType);
    if ({ScheduleView.upcoming, ScheduleView.overdue}.contains(view)) {
      q = q.where('status', isEqualTo: 'pending');
    } else if (view == ScheduleView.done) {
      q = q.where('status', isEqualTo: 'done');
    }
    if (date != null || view == ScheduleView.today) {
      final day = date ?? now;
      final start = DateTime(day.year, day.month, day.day);
      final end = DateTime(day.year, day.month, day.day + 1);
      q = q
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('date', isLessThan: Timestamp.fromDate(end));
    }
    if (view == ScheduleView.upcoming) {
      q = q.where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(now));
    }
    if (view == ScheduleView.overdue) {
      q = q.where('date', isLessThan: Timestamp.fromDate(now));
    }
    return q.orderBy(
      'date',
      descending: view == ScheduleView.done || view == ScheduleView.overdue,
    );
  }
}

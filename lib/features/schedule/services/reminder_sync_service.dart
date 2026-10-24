import '../../../core/services/local_reminder_service.dart';
import 'schedule_service.dart';

class ReminderSyncService {
  ReminderSyncService({
    ScheduleService? schedules,
    LocalReminderService? reminders,
  }) : _schedules = schedules ?? ScheduleService(),
       _reminders = reminders ?? LocalReminderService();
  final ScheduleService _schedules;
  final LocalReminderService _reminders;
  Future<String>? _running;
  bool _closed = false;
  static Future<void>? _queue;

  static Future<T> _enqueue<T>(Future<T> Function() action) {
    final previous = _queue;
    final result = previous == null
        ? Future<T>.sync(action)
        : previous.then((_) => action());
    late final Future<void> tail;
    tail = result.then<void>((_) {}, onError: (Object _) {}).whenComplete(() {
      if (identical(_queue, tail)) _queue = null;
    });
    _queue = tail;
    return result;
  }

  Future<String> sync() => _closed
      ? Future.value('Sesi pengingat telah berakhir.')
      : _running ??= _enqueue(_sync).whenComplete(() => _running = null);

  Future<String> _sync() async {
    try {
      final items = await _schedules.reminderCandidates(DateTime.now());
      final desired = items.map((s) => s.id).toSet();
      for (final id in await _reminders.pendingScheduleIds()) {
        if (!desired.contains(id)) await _reminders.cancelScheduleReminder(id);
      }
      if (!await _reminders.requestPermission()) {
        return 'Data jadwal tersimpan. Izin pengingat perangkat belum diberikan. Aktifkan izin lalu sinkronkan ulang.';
      }
      var scheduled = 0;
      final ids = <int>{};
      for (final item in items) {
        if (_closed) return 'Sesi pengingat telah berakhir.';
        if (!ids.add(stableReminderId(item.id))) {
          throw StateError(
            'ID pengingat bertabrakan; sebagian pengingat belum terpasang.',
          );
        }
        await _reminders.scheduleScheduleReminder(
          scheduleId: item.id,
          title: item.title,
          scheduledAt: item.scheduledAt,
          body: item.scheduleType,
        );
        scheduled++;
      }
      return '$scheduled pengingat perangkat disinkronkan (maksimal 50 jadwal dalam 14 hari).';
    } catch (_) {
      return 'Data jadwal tetap tersimpan. Sinkronisasi pengingat perangkat belum berhasil; coba lagi saat aplikasi aktif.';
    }
  }

  Future<void> cancel(String id) =>
      _enqueue(() => _reminders.cancelScheduleReminder(id));
  Future<void> clear() {
    _closed = true;
    return _enqueue(_reminders.cancelAll);
  }
}

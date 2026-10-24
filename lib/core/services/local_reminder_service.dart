import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class LocalReminderService {
  LocalReminderService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    tz.initializeTimeZones();

    const settings = InitializationSettings(
      android: AndroidInitializationSettings('ic_stat_seicycle'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
      macOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );
    await _plugin.initialize(settings: settings);
    _initialized = true;
  }

  Future<bool> requestPermission() async {
    await initialize();
    final androidGranted = await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
    final iosGranted = await _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);
    final macGranted = await _plugin
        .resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    return androidGranted ?? iosGranted ?? macGranted ?? false;
  }

  Future<void> scheduleScheduleReminder({
    required String scheduleId,
    required String title,
    required DateTime scheduledAt,
    String? body,
  }) async {
    if (!scheduledAt.isAfter(DateTime.now())) return;
    await initialize();

    await _plugin.zonedSchedule(
      id: stableReminderId(scheduleId),
      title: title,
      body: body ?? 'Pengingat jadwal operasional SeiCycle.',
      scheduledDate: tz.TZDateTime.from(scheduledAt, tz.UTC),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'seicycle_schedule_reminders',
          'Pengingat Jadwal',
          channelDescription: 'Pengingat lokal untuk jadwal operasional.',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
        macOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: 'schedule:$scheduleId',
    );
  }

  Future<void> cancelScheduleReminder(String scheduleId) async {
    await initialize();
    await _plugin.cancel(id: stableReminderId(scheduleId));
  }

  Future<Set<String>> pendingScheduleIds() async {
    await initialize();
    final requests = await _plugin.pendingNotificationRequests();
    final ids = <String>{};
    for (final request in requests.where(
      (r) => r.payload?.startsWith('schedule:') == true,
    )) {
      final id = request.payload!.substring(9);
      if (request.id != stableReminderId(id)) {
        // Retire reminders installed by the legacy hashCode implementation.
        await _plugin.cancel(id: request.id);
      } else {
        ids.add(id);
      }
    }
    return ids;
  }

  Future<void> cancelAll() async {
    await initialize();
    await _plugin.cancelAll();
  }
}

// Bounded DJB2: exact integer math on native Dart and JavaScript.
int stableReminderId(String value) {
  var hash = 5381;
  for (final unit in value.codeUnits) {
    hash = ((hash * 33) ^ unit) & 0x7fffffff;
  }
  return hash & 0x7fffffff;
}

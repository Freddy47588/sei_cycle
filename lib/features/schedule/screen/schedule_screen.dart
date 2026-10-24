import '../../../core/utils/audit_mode.dart';
import 'package:flutter/material.dart';
import '../../../core/constants/farm_modules.dart';
import '../../../core/utils/delete_confirmation.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_ui.dart';
import '../../../core/widgets/feature_page.dart';
import '../../../core/widgets/firestore_paged_list.dart';
import '../../../theme/app_theme.dart';
import '../../profile/models/app_user.dart';
import '../../logbook/screen/logbook_screen.dart';
import '../../logbook/services/logbook_service.dart';
import '../../notification/services/notification_service.dart';
import '../models/schedule_item.dart';
import '../models/schedule_filter.dart';
import '../services/schedule_service.dart';
import '../services/reminder_sync_service.dart';
import '../widgets/schedule_form.dart';

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({
    required this.profile,
    this.service,
    this.reminders,
    this.logbooks,
    this.notifications,
    this.batchId,
    super.key,
  });
  final AppUser profile;
  final ScheduleService? service;
  final ReminderSyncService? reminders;
  final LogbookService? logbooks;
  final NotificationService? notifications;
  final String? batchId;
  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  late final _service = widget.service ?? ScheduleService();
  late final _reminders =
      widget.reminders ?? ReminderSyncService(schedules: _service);
  late ScheduleView _view = widget.batchId == null
      ? ScheduleView.today
      : ScheduleView.all;
  String? _moduleType;
  DateTime? _date;
  int _revision = 0;
  final _busy = <String>{};
  bool _syncing = false;
  String _reminderMessage =
      'Pengingat lokal diperiksa saat login, aplikasi aktif, atau sinkronisasi. Waktu mengikuti perangkat.';
  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _sync() async {
    if (!mounted || _syncing) return;
    setState(() => _syncing = true);
    final message = await _reminders.sync();
    if (mounted) {
      setState(() {
        _reminderMessage = message;
        _syncing = false;
      });
      _message(message);
    }
  }

  Future<void> _afterChange(String id) async {
    // Cancel the old device time even if a following Firestore read fails.
    try {
      await _reminders.cancel(id);
    } catch (_) {
      /* sync reports device failures below. */
    }
    await _sync();
  }

  Future<void> _form([ScheduleItem? item]) async {
    final id = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ScheduleForm(
        service: _service,
        userId: widget.profile.uid,
        item: item,
        logbooks: widget.logbooks,
      ),
    );
    if (id != null && mounted) {
      _message('Jadwal tersimpan. Pengingat perangkat sedang disinkronkan.');
      setState(() => _revision++);
      await _afterChange(id);
    }
  }

  Future<void> _status(ScheduleItem item, String status) async {
    if (_busy.contains(item.id)) return;
    setState(() => _busy.add(item.id));
    String reason = '';
    if (status == 'skipped') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Lewati kegiatan'),
          content: TextField(
            onChanged: (value) => reason = value,
            decoration: const InputDecoration(labelText: 'Alasan (opsional)'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Tandai Dilewati'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) {
        if (mounted) setState(() => _busy.remove(item.id));
        return;
      }
    }
    try {
      await _service.updateStatus(
        item.id,
        status,
        userId: widget.profile.uid,
        expectedUpdatedAt: item.updatedAt,
        reason: reason,
      );
      _message(
        status == 'done'
            ? 'Kegiatan ditandai selesai.'
            : 'Kegiatan ditandai dilewati.',
      );
      if (mounted) setState(() => _revision++);
      await _afterChange(item.id);
    } catch (e) {
      _message('Status belum tersimpan: $e');
    } finally {
      if (mounted) setState(() => _busy.remove(item.id));
    }
  }

  Future<void> _delete(ScheduleItem item) async {
    if (!await confirmDelete(
          context,
          title: 'Hapus jadwal?',
          message: 'Hapus kegiatan pending ini dari kalender?',
        ) ||
        !mounted) {
      return;
    }
    try {
      await _service.delete(
        item.id,
        userId: widget.profile.uid,
        expectedUpdatedAt: item.updatedAt,
      );
      if (mounted) setState(() => _revision++);
      _message('Jadwal dihapus.');
      await _afterChange(item.id);
    } catch (e) {
      _message('Jadwal belum dihapus: $e');
    }
  }

  Future<void> _record(ScheduleItem item) async {
    final logs = widget.logbooks ?? LogbookService();
    try {
      final batch = item.batchId == null
          ? null
          : await logs.batches.getBatch(item.batchId!);
      final valid =
          batch != null &&
          batch.status == 'active' &&
          batch.input.moduleType == item.moduleId;
      if (!mounted) return;
      if (item.batchId != null && !valid) {
        _message(
          'Batch ${item.batchId} tidak aktif. Form dibuka tanpa batch; pilih konteks kegiatan secara eksplisit.',
        );
      }
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            appBar: AppBar(title: const Text('Catat di Logbook')),
            body: LogbookScreen(
              profile: widget.profile,
              service: logs,
              initialModuleId: item.moduleId,
              initialBatch: valid ? batch : null,
              scheduleTitle: item.title,
            ),
          ),
        ),
      );
    } catch (e) {
      _message('Konteks Logbook belum dapat dibuka: $e');
    }
  }

  @override
  Widget build(BuildContext context) => FeaturePage(
    title: 'Kalender Operasional',
    subtitle: widget.batchId == null
        ? 'Checklist pakan, perawatan, pemupukan, dan panen Kebun Sei. Data bertanda sampel tidak disertakan.'
        : 'Jadwal Batch ${widget.batchId}',
    actions: [
      if (widget.profile.canManageSchedules)
        FilledButton.icon(
          onPressed: _form,
          icon: const Icon(Icons.add),
          label: const Text('Tambah jadwal'),
        ),
      IconButton(
        onPressed: () => setState(() => _revision++),
        tooltip: 'Muat ulang jadwal',
        icon: const Icon(Icons.refresh),
      ),
    ],
    child: Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final view in ScheduleView.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(scheduleViewLabel(view)),
                    selected: _view == view,
                    labelStyle: TextStyle(
                      color: _view == view
                          ? Colors.white
                          : AppColors.primaryGreen,
                    ),
                    onSelected: (_) => setState(() {
                      _view = view;
                      _date = null;
                    }),
                  ),
                ),
            ],
          ),
        ),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('Modul, tanggal & pengingat perangkat'),
          children: [
            DropdownButtonFormField<String>(
              initialValue: _moduleType ?? '',
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Modul jadwal'),
              items: [
                const DropdownMenuItem(value: '', child: Text('Semua Modul')),
                for (final m in FarmModules.values)
                  DropdownMenuItem(value: m.id, child: Text(m.name)),
              ],
              onChanged: (v) =>
                  setState(() => _moduleType = v == '' ? null : v),
            ),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: _date ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (date != null && mounted) setState(() => _date = date);
                  },
                  icon: const Icon(Icons.date_range),
                  label: Text(
                    _date == null
                        ? 'Pilih tanggal'
                        : shortDateFormat.format(_date!),
                  ),
                ),
                if (_date != null)
                  TextButton(
                    onPressed: () => setState(() => _date = null),
                    child: const Text('Hapus tanggal'),
                  ),
                TextButton.icon(
                  onPressed: _syncing ? null : _sync,
                  icon: const Icon(Icons.notifications_active_outlined),
                  label: Text(
                    _syncing ? 'Menyinkronkan...' : 'Sinkronkan Pengingat',
                  ),
                ),
              ],
            ),
            Text(_reminderMessage),
          ],
        ),
        Expanded(
          child: FirestorePagedList<ScheduleItem>(
            idOf: (item) => item.id,
            queryKey: (_view, _date, _revision, widget.batchId, _moduleType),
            load: (cursor) => _service.fetchPage(
              filter: ScheduleFilter(
                view: _view,
                date: _date,
                batchId: widget.batchId,
                moduleType: _moduleType,
              ),
              cursor: cursor,
            ),
            onLoaded: !readOnlyAudit && widget.profile.canManageSchedules
                ? (items) async {
                    final service =
                        widget.notifications ?? NotificationService();
                    for (final item
                        in items
                            .where(
                              (s) =>
                                  s.status == 'pending' &&
                                  s.scheduledAt.isBefore(DateTime.now()),
                            )
                            .take(5)) {
                      await service.createScheduleOverdueAlert(
                        scheduleId: item.id,
                        title: item.title,
                        userId: widget.profile.uid,
                        role: widget.profile.effectiveRole,
                      );
                    }
                  }
                : null,
            itemBuilder: (item) => AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  StatusBadge(
                    label: item.status == 'done'
                        ? 'Selesai'
                        : item.status == 'skipped'
                        ? 'Dilewati'
                        : item.scheduledAt.isBefore(DateTime.now())
                        ? 'Terlewat'
                        : 'Menunggu',
                    color: item.status == 'done'
                        ? AppColors.success
                        : item.status == 'skipped'
                        ? AppColors.textMuted
                        : AppColors.primaryGreen,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${FarmModules.nameOf(item.moduleId)} - ${item.scheduleType}',
                  ),
                  Text(
                    item.batchId == null
                        ? 'Tanpa Batch \u2014 Aktivitas Umum'
                        : 'Batch: ${item.batchId}',
                  ),
                  Text(dateTimeFormat.format(item.scheduledAt)),
                  if (item.note.isNotEmpty)
                    Text(
                      item.note,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (item.completedAt != null)
                    Text(
                      'Selesai oleh ${item.completedBy} - ${dateTimeFormat.format(item.completedAt!)}',
                    ),
                  if (item.skippedAt != null)
                    Text(
                      'Dilewati oleh ${item.skippedBy} - ${dateTimeFormat.format(item.skippedAt!)} ${item.skipReason}',
                    ),
                  if (widget.profile.canManageSchedules)
                    Wrap(
                      spacing: 8,
                      children: [
                        if (item.status == 'pending') ...[
                          FilledButton.tonal(
                            onPressed: _busy.contains(item.id)
                                ? null
                                : () => _status(item, 'done'),
                            child: const Text('Tandai Selesai'),
                          ),
                          TextButton(
                            onPressed: _busy.contains(item.id)
                                ? null
                                : () => _status(item, 'skipped'),
                            child: const Text('Lewati'),
                          ),
                          IconButton(
                            onPressed: _busy.contains(item.id)
                                ? null
                                : () => _form(item),
                            tooltip: 'Edit jadwal',
                            icon: const Icon(Icons.edit_outlined),
                          ),
                          if (widget.profile.canDeleteSchedules)
                            IconButton(
                              onPressed: _busy.contains(item.id)
                                  ? null
                                  : () => _delete(item),
                              tooltip: 'Hapus jadwal',
                              icon: const Icon(Icons.delete_outline),
                            ),
                        ],
                        TextButton.icon(
                          onPressed: () => _record(item),
                          icon: const Icon(Icons.menu_book_outlined),
                          label: const Text('Catat di Logbook'),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

import 'package:flutter/material.dart';

import '../../../core/utils/delete_confirmation.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/operation_feedback.dart';
import '../../../core/widgets/app_ui.dart';
import '../../../core/widgets/async_state_widgets.dart';
import '../../../core/widgets/feature_page.dart';
import '../../../core/widgets/operational_reference_screen.dart';
import '../../../theme/app_theme.dart';
import '../../profile/models/app_user.dart';
import '../models/app_notification.dart';
import '../services/notification_service.dart';

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({
    required this.profile,
    this.notifications,
    this.notificationService,
    super.key,
  });
  final Stream<List<AppNotification>>? notifications;
  final NotificationService? notificationService;

  final AppUser profile;

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  late NotificationService _service =
      widget.notificationService ?? NotificationService();
  String? _type;
  bool _unreadOnly = false;
  Stream<List<AppNotification>>? _stream;
  String? _streamType;
  bool _busy = false;

  (String, String, bool) get _sessionIdentity => (
    widget.profile.uid,
    widget.profile.effectiveRole,
    widget.profile.isActive,
  );

  @override
  void didUpdateWidget(covariant NotificationScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile.uid != widget.profile.uid ||
        oldWidget.profile.effectiveRole != widget.profile.effectiveRole ||
        oldWidget.profile.isActive != widget.profile.isActive ||
        oldWidget.notificationService != widget.notificationService) {
      _stream = null;
      if (oldWidget.notificationService != widget.notificationService) {
        _service = widget.notificationService ?? NotificationService();
      }
    }
  }

  Future<void> _markAsRead(AppNotification notification) async {
    if (_busy) return;
    await runOperationWithFeedback(
      context,
      operation: () =>
          _service.markAsRead(notification.id, userId: widget.profile.uid),
      successMessage: 'Notifikasi ditandai sudah dibaca.',
    );
  }

  Future<void> _markAllAsRead() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await runOperationWithFeedback(
        context,
        operation: () => _service.markAllAsRead(
          userId: widget.profile.uid,
          role: widget.profile.effectiveRole,
        ),
        successMessage: 'Semua notifikasi ditandai sudah dibaca.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Stream<List<AppNotification>> _notifications() {
    if (!widget.profile.isActive) {
      return _stream ??= Stream.value(const <AppNotification>[]);
    }
    if (widget.notifications != null) return widget.notifications!;
    if (_stream == null || _streamType != _type) {
      _streamType = _type;
      _stream = _service.watchNotifications(
        userId: widget.profile.uid,
        role: widget.profile.effectiveRole,
        type: _type,
      );
    }
    return _stream!;
  }

  Future<void> _delete(AppNotification notification) async {
    final confirmed = await confirmDelete(
      context,
      title: 'Hapus notifikasi?',
      message: 'Notifikasi "${notification.title}" akan dihapus dari daftar.',
    );
    if (!confirmed || !mounted) return;

    await runOperationWithFeedback(
      context,
      operation: () =>
          _service.delete(notification.id, userId: widget.profile.uid),
      successMessage: 'Notifikasi dihapus.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return FeaturePage(
      title: 'Notifikasi & Pengingat',
      subtitle: 'Inbox aplikasi dan pengingat lokal dari kegiatan tercatat',
      actions: [
        IconButton(
          tooltip: 'Muat ulang',
          onPressed: () => setState(() => _stream = null),
          icon: const Icon(Icons.refresh),
        ),
        FilterChip(
          label: const Text('Belum dibaca'),
          selected: _unreadOnly,
          onSelected: (v) => setState(() => _unreadOnly = v),
        ),
        OutlinedButton.icon(
          onPressed: _busy || !widget.profile.isActive ? null : _markAllAsRead,
          icon: const Icon(Icons.done_all_rounded),
          label: const Text('Tandai semua'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _notificationFilters.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final filter = _notificationFilters[index];
                return AppFilterChip(
                  selected: _type == filter.type,
                  label: filter.label,
                  icon: filter.icon,
                  color: filter.color,
                  onSelected: () => setState(() => _type = filter.type),
                );
              },
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: StreamBuilder<List<AppNotification>>(
              key: ValueKey((_sessionIdentity, widget.notifications)),
              stream: _notifications(),
              builder: (context, snapshot) {
                final state = asyncSnapshotState(snapshot);
                if (snapshot.hasError) {
                  return ErrorState(
                    message: '${snapshot.error}',
                    onRetry: () => setState(() => _stream = null),
                  );
                }
                if (state != null) return state;

                final notifications = snapshot.requireData
                    .where((n) => !_unreadOnly || !n.isRead)
                    .toList();
                if (notifications.isEmpty) {
                  return const EmptyState(
                    title: 'Belum ada notifikasi',
                    message:
                        'Alert stok, jadwal, dan sistem akan muncul di sini saat tersedia.',
                    icon: Icons.notifications_none_outlined,
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.only(bottom: 12),
                  itemCount: notifications.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final notification = notifications[index];
                    final canDelete =
                        widget.profile.isAdmin ||
                        notification.userId == widget.profile.uid;
                    return _DismissibleNotification(
                      notification: notification,
                      canDelete: canDelete,
                      onDelete: () async {
                        await _delete(notification);
                        return false;
                      },
                      child: _NotificationCard(
                        notification: notification,
                        onOpen:
                            canOpenOperationalReference(
                              widget.profile,
                              notification.relatedCollection,
                              notification.relatedId,
                            )
                            ? () => Navigator.push(
                                context,
                                MaterialPageRoute<void>(
                                  builder: (_) => OperationalReferenceScreen(
                                    profile: widget.profile,
                                    collection: notification.relatedCollection,
                                    documentId: notification.relatedId,
                                  ),
                                ),
                              )
                            : null,
                        onMarkRead: notification.isRead
                            ? null
                            : () => _markAsRead(notification),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

const _notificationFilters = [
  _NotificationFilter(
    type: null,
    label: 'Semua',
    icon: Icons.notifications_none_rounded,
    color: AppColors.info,
  ),
  _NotificationFilter(
    type: 'production_reminder',
    label: 'Jadwal Pakan',
    icon: Icons.notifications_active_outlined,
    color: AppColors.primaryGreen,
  ),
  _NotificationFilter(
    type: 'schedule_overdue',
    label: 'Jadwal Terlewat',
    icon: Icons.warning_amber_rounded,
    color: AppColors.warning,
  ),
  _NotificationFilter(
    type: 'low_stock',
    label: 'Stok Rendah',
    icon: Icons.inventory_2_outlined,
    color: AppColors.error,
  ),
  _NotificationFilter(
    type: 'system',
    label: 'Alert Sistem',
    icon: Icons.info_outline,
    color: AppColors.info,
  ),
];

class _NotificationFilter {
  const _NotificationFilter({
    required this.type,
    required this.label,
    required this.icon,
    required this.color,
  });

  final String? type;
  final String label;
  final IconData icon;
  final Color color;
}

class _DismissibleNotification extends StatelessWidget {
  const _DismissibleNotification({
    required this.notification,
    required this.canDelete,
    required this.onDelete,
    required this.child,
  });

  final AppNotification notification;
  final bool canDelete;
  final Future<bool> Function() onDelete;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!canDelete) return child;

    return Dismissible(
      key: ValueKey('notification_${notification.id}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => onDelete(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: AppColors.error,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      child: child,
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.notification,
    this.onOpen,
    required this.onMarkRead,
  });

  final AppNotification notification;
  final VoidCallback? onMarkRead;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final color = _typeColor(notification.type);
    return AppCard(
      color: notification.isRead ? AppColors.surface : AppColors.softGreen,
      borderColor: notification.isRead
          ? AppColors.border
          : color.withValues(alpha: 0.35),
      padding: EdgeInsets.zero,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
              child: Center(
                child: AppIconBox(
                  icon: _typeIcon(notification.type),
                  color: color,
                  size: 44,
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notification.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      notification.body,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textMedium,
                        height: 1.35,
                      ),
                    ),
                    if (onOpen != null)
                      TextButton(
                        onPressed: onOpen,
                        child: const Text('Lihat catatan terkait'),
                      ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        StatusBadge(
                          label: _typeLabel(notification.type),
                          color: AppColors.primaryGreen,
                        ),
                        StatusBadge(
                          label: notification.scheduledAt == null
                              ? shortDateFormat.format(notification.createdAt)
                              : timeFormat.format(notification.scheduledAt!),
                          color: AppColors.textMuted,
                          icon: Icons.schedule_rounded,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Center(
              child: onMarkRead == null
                  ? const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(
                        Icons.done_all_rounded,
                        size: 18,
                        color: AppColors.textMuted,
                        semanticLabel: 'Sudah dibaca',
                      ),
                    )
                  : IconButton(
                      onPressed: onMarkRead,
                      icon: const Icon(Icons.check_circle_rounded),
                      color: color,
                      tooltip: 'Tandai dibaca',
                    ),
            ),
            Container(
              width: 4,
              margin: const EdgeInsets.fromLTRB(8, 18, 12, 18),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Color _typeColor(String type) => switch (type) {
  'low_stock' => AppColors.warning,
  'schedule_overdue' => AppColors.error,
  'production_reminder' => AppColors.primaryGreen,
  _ => AppColors.info,
};

IconData _typeIcon(String type) => switch (type) {
  'low_stock' => Icons.inventory_2_outlined,
  'schedule_overdue' => Icons.event_busy_outlined,
  'production_reminder' => Icons.notifications_active_outlined,
  _ => Icons.info_outline,
};

String _typeLabel(String type) => switch (type) {
  'low_stock' => 'Stok rendah',
  'schedule_overdue' => 'Jadwal terlewat',
  'production_reminder' => 'Jadwal pakan',
  _ => 'Alert sistem',
};

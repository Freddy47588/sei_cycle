import 'dart:async';
import 'package:flutter/material.dart';
import '../features/schedule/services/reminder_sync_service.dart';
import 'package:intl/intl.dart';

import '../features/admin/screen/admin_management_screen.dart';
import '../features/dashboard/screen/dashboard_screen.dart';
import '../features/education/screen/education_screen.dart';
import '../features/finance/screen/finance_screen.dart';
import '../features/sales/screen/sales_screen.dart';
import '../features/circular_flow/screen/circular_flow_screen.dart';
import '../features/inventory/screen/inventory_screen.dart';
import '../features/logbook/screen/logbook_screen.dart';
import '../features/notification/screen/notification_screen.dart';
import '../features/notification/services/notification_service.dart';
import '../features/profile/models/app_user.dart';
import '../features/profile/screen/profile_screen.dart';
import '../features/recommendations/screen/recommendation_screen.dart';
import '../features/reports/screens/report_screen.dart';
import '../features/schedule/screen/schedule_screen.dart';
import '../theme/app_theme.dart';
import '../core/widgets/kebun_sei_logo.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    required this.profile,
    this.unreadCountStream,
    this.pageBuilder,
    super.key,
  });

  final Stream<int>? unreadCountStream;
  final Widget Function(String destination)? pageBuilder;

  final AppUser profile;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  ReminderSyncService? _reminderSync;
  int _selectedIndex = 0;
  bool _logbookVisited = false;
  Widget? _injectedDraftPage;
  GlobalKey _draftKey = GlobalKey();
  late Stream<int> _unreadCountStream;

  (String, String, bool) get _sessionIdentity => (
    widget.profile.uid,
    widget.profile.effectiveRole,
    widget.profile.isActive,
  );

  void _watchUnreadCount() {
    _unreadCountStream = !widget.profile.isActive
        ? Stream<int>.value(0)
        : widget.unreadCountStream ??
              NotificationService().watchUnreadCount(
                userId: widget.profile.uid,
                role: widget.profile.effectiveRole,
              );
  }

  @override
  void initState() {
    super.initState();
    if (widget.pageBuilder == null && widget.profile.isActive) {
      WidgetsBinding.instance.addObserver(this);
      _reminderSync = ReminderSyncService();
      unawaited(_syncReminders());
    }
    _watchUnreadCount();
  }

  @override
  void didUpdateWidget(covariant AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sessionChanged =
        oldWidget.profile.uid != widget.profile.uid ||
        oldWidget.profile.effectiveRole != widget.profile.effectiveRole ||
        oldWidget.profile.isActive != widget.profile.isActive;
    if (sessionChanged) {
      _draftKey = GlobalKey();
      _logbookVisited = false;
      _injectedDraftPage = null;
      _selectedIndex = 0;
      unawaited(_reminderSync?.clear());
      _reminderSync = null;
      WidgetsBinding.instance.removeObserver(this);
      if (widget.pageBuilder == null && widget.profile.isActive) {
        WidgetsBinding.instance.addObserver(this);
        _reminderSync = ReminderSyncService();
        unawaited(_syncReminders());
      }
    }
    if (sessionChanged ||
        oldWidget.unreadCountStream != widget.unreadCountStream) {
      _watchUnreadCount();
    }
  }

  Future<void> _syncReminders() async {
    final message = await _reminderSync?.sync();
    if (mounted && message != null && !message.contains('disinkronkan')) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_syncReminders());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Prevent reminders for the previous account surviving a logout.
    unawaited(
      _reminderSync?.clear().catchError((Object _) {}) ?? Future<void>.value(),
    );
    super.dispose();
  }

  List<_Destination> get _destinations => <_Destination>[
    _Destination(
      label: 'Dashboard',
      icon: Icons.dashboard_outlined,
      selectedIcon: Icons.dashboard_rounded,
      builder: () => DashboardScreen(profile: widget.profile),
    ),
    if (widget.profile.canViewLogbooks)
      _Destination(
        label: 'Logbook',
        icon: Icons.menu_book_outlined,
        selectedIcon: Icons.menu_book_rounded,
        builder: () => LogbookScreen(profile: widget.profile),
      ),
    _Destination(
      label: 'Edukasi',
      icon: Icons.school_outlined,
      selectedIcon: Icons.school_rounded,
      builder: () => EducationScreen(profile: widget.profile),
    ),
    _Destination(
      label: 'Notifikasi',
      icon: Icons.notifications_none_outlined,
      selectedIcon: Icons.notifications_rounded,
      builder: () => NotificationScreen(profile: widget.profile),
      isBadged: true,
    ),
    if (widget.profile.canViewInventory)
      _Destination(
        label: 'Inventaris',
        icon: Icons.inventory_2_outlined,
        selectedIcon: Icons.inventory_2_rounded,
        builder: () => InventoryScreen(profile: widget.profile),
      ),
    if (widget.profile.canViewSchedules)
      _Destination(
        label: 'Jadwal',
        icon: Icons.event_note_outlined,
        selectedIcon: Icons.event_note_rounded,
        builder: () => ScheduleScreen(profile: widget.profile),
      ),
    if (widget.profile.canViewFinance)
      _Destination(
        label: 'Keuangan',
        icon: Icons.account_balance_wallet_outlined,
        selectedIcon: Icons.account_balance_wallet_rounded,
        builder: () => FinanceScreen(profile: widget.profile),
      ),
    if (widget.profile.canViewRecommendations)
      _Destination(
        label: 'Rekomendasi',
        icon: Icons.auto_awesome_outlined,
        selectedIcon: Icons.auto_awesome_rounded,
        builder: () => RecommendationScreen(profile: widget.profile),
      ),
    if (widget.profile.canViewReports)
      _Destination(
        label: 'Laporan',
        icon: Icons.analytics_outlined,
        selectedIcon: Icons.analytics_rounded,
        builder: () => ReportScreen(profile: widget.profile),
      ),
    _Destination(
      label: 'Profil',
      icon: Icons.person_outline,
      selectedIcon: Icons.person_rounded,
      builder: () => ProfileScreen(profile: widget.profile),
    ),
    if (widget.profile.canViewSales)
      _Destination(
        label: 'Penjualan',
        icon: Icons.point_of_sale_outlined,
        selectedIcon: Icons.point_of_sale,
        builder: () => SalesScreen(profile: widget.profile),
      ),
    if (widget.profile.canViewCircularFlows)
      _Destination(
        label: 'Aliran Nutrisi',
        icon: Icons.recycling_outlined,
        selectedIcon: Icons.recycling,
        builder: () => CircularFlowScreen(profile: widget.profile),
      ),
    if (widget.profile.isActive && widget.profile.isAdmin)
      _Destination(
        label: 'Kelola Data Admin',
        icon: Icons.admin_panel_settings_outlined,
        selectedIcon: Icons.admin_panel_settings,
        builder: () => AdminManagementScreen(profile: widget.profile),
      ),
  ];

  void _select(int index) {
    if (index < 0 || index >= _destinations.length) return;
    if (index == _selectedIndex) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _selectedIndex = index;
      if (_destinations[index].label == 'Logbook') {
        _logbookVisited = true;
        _injectedDraftPage ??= widget.pageBuilder?.call('Logbook');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final destinations = _destinations;
    if (_selectedIndex >= destinations.length) _selectedIndex = 0;

    return StreamBuilder<int>(
      key: ValueKey(_sessionIdentity),
      stream: _unreadCountStream,
      initialData: 0,
      builder: (context, snapshot) {
        final unreadCount = snapshot.data ?? 0;
        return LayoutBuilder(
          builder: (context, constraints) {
            final isLogbook = destinations[_selectedIndex].label == 'Logbook';
            final content = IndexedStack(
              key: ValueKey(_sessionIdentity),
              index: isLogbook ? 0 : 1,
              children: [
                TickerMode(
                  enabled: isLogbook,
                  child: KeyedSubtree(
                    key: _draftKey,
                    child: _logbookVisited && widget.profile.canViewLogbooks
                        ? _injectedDraftPage ??
                              LogbookScreen(profile: widget.profile)
                        : const SizedBox.shrink(),
                  ),
                ),
                isLogbook
                    ? const SizedBox.shrink()
                    : widget.pageBuilder?.call(
                            destinations[_selectedIndex].label,
                          ) ??
                          destinations[_selectedIndex].builder(),
              ],
            );
            if (constraints.maxWidth >= AppBreakpoints.desktop) {
              return _DesktopShell(
                profile: widget.profile,
                destinations: destinations,
                selectedIndex: _selectedIndex,
                onSelected: _select,
                body: content,
                unreadCount: unreadCount,
              );
            }
            return _MobileShell(
              profile: widget.profile,
              destinations: destinations,
              selectedIndex: _selectedIndex,
              onSelected: _select,
              body: content,
              unreadCount: unreadCount,
            );
          },
        );
      },
    );
  }
}

class _Destination {
  const _Destination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.builder,
    this.isBadged = false,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget Function() builder;
  final bool isBadged;
}

class _MobileShell extends StatelessWidget {
  const _MobileShell({
    required this.profile,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
    required this.body,
    required this.unreadCount,
  });

  final AppUser profile;
  final List<_Destination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final Widget body;
  final int unreadCount;

  @override
  Widget build(BuildContext context) {
    final profileIndex = destinations.indexWhere(
      (destination) => destination.label == 'Profil',
    );

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        titleSpacing: 16,
        title: Row(
          children: [
            const KebunSeiLogo(size: 46),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'SeiCycle',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          if (profileIndex != selectedIndex)
            IconButton(
              onPressed: () => onSelected(profileIndex),
              tooltip: 'Buka profil',
              icon: const Icon(Icons.person_outline_rounded, size: 26),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: body,
      bottomNavigationBar: _MobileNavigation(
        destinations: destinations,
        selectedIndex: selectedIndex,
        onSelected: onSelected,
        unreadCount: unreadCount,
      ),
    );
  }
}

class _MobileNavigation extends StatelessWidget {
  const _MobileNavigation({
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
    required this.unreadCount,
  });

  final List<_Destination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final int unreadCount;

  @override
  Widget build(BuildContext context) {
    final hasOverflow = destinations.length > 5;
    final visibleCount = hasOverflow ? 4 : destinations.length;
    final navigationIndex = hasOverflow && selectedIndex >= visibleCount
        ? visibleCount
        : selectedIndex;

    final navigation = DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: NavigationBar(
        selectedIndex: navigationIndex,
        onDestinationSelected: (index) {
          if (!hasOverflow || index < visibleCount) {
            onSelected(index);
            return;
          }
          _showMore(context, visibleCount);
        },
        destinations: [
          for (var index = 0; index < visibleCount; index++)
            NavigationDestination(
              icon: destinations[index].isBadged && unreadCount > 0
                  ? Badge.count(
                      count: unreadCount,
                      child: Icon(destinations[index].icon),
                    )
                  : Icon(destinations[index].icon),
              selectedIcon: destinations[index].isBadged && unreadCount > 0
                  ? Badge.count(
                      count: unreadCount,
                      child: Icon(destinations[index].selectedIcon),
                    )
                  : Icon(destinations[index].selectedIcon),
              label: destinations[index].label,
            ),
          if (hasOverflow)
            const NavigationDestination(
              icon: Icon(Icons.grid_view_outlined),
              selectedIcon: Icon(Icons.grid_view_rounded),
              label: 'Lainnya',
            ),
        ],
      ),
    );
    return SafeArea(top: false, child: navigation);
  }

  Future<void> _showMore(BuildContext context, int startIndex) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) {
        final mediaQuery = MediaQuery.of(context);
        final maxSheetHeight = mediaQuery.size.height * 0.72;

        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxSheetHeight),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              16,
              0,
              16,
              mediaQuery.padding.bottom + 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                  child: Text(
                    'Menu lainnya',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                for (
                  var index = startIndex;
                  index < destinations.length;
                  index++
                )
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: ListTile(
                      selected: index == selectedIndex,
                      selectedColor: AppColors.primaryGreen,
                      selectedTileColor: AppColors.softGreen,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      leading: Icon(
                        index == selectedIndex
                            ? destinations[index].selectedIcon
                            : destinations[index].icon,
                      ),
                      title: Text(destinations[index].label),
                      trailing: index == selectedIndex
                          ? const Icon(Icons.check_rounded, size: 20)
                          : null,
                      onTap: () {
                        Navigator.pop(context);
                        onSelected(index);
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DesktopShell extends StatelessWidget {
  const _DesktopShell({
    required this.profile,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
    required this.body,
    required this.unreadCount,
  });

  final AppUser profile;
  final List<_Destination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final Widget body;
  final int unreadCount;

  @override
  Widget build(BuildContext context) {
    final date = DateFormat('EEEE, d MMM yyyy', 'id_ID').format(DateTime.now());

    return Scaffold(
      body: Row(
        children: [
          SizedBox(
            width: 248,
            child: Material(
              color: AppColors.surface,
              child: SafeArea(
                right: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 88,
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      color: AppColors.primaryGreen,
                      child: const Row(
                        children: [
                          KebunSeiLogo(size: 56),
                          SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'SeiCycle',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  'Operasional Kebun Sei',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(18, 18, 18, 8),
                      child: Text(
                        'MENU UTAMA',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        itemCount: destinations.length,
                        itemBuilder: (context, index) {
                          final destination = destinations[index];
                          final selected = index == selectedIndex;
                          final showBadge =
                              destination.isBadged && unreadCount > 0;
                          final firstSecondary = destinations.indexWhere(
                            (item) => item.label == 'Inventaris',
                          );
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (index == firstSecondary)
                                const Padding(
                                  padding: EdgeInsets.fromLTRB(8, 20, 8, 8),
                                  child: Text(
                                    'LAINNYA',
                                    style: TextStyle(
                                      color: AppColors.textMuted,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 1.1,
                                    ),
                                  ),
                                ),
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: ListTile(
                                  selected: selected,
                                  selectedColor: AppColors.primaryGreen,
                                  selectedTileColor: AppColors.softGreen,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(11),
                                  ),
                                  leading: showBadge
                                      ? Badge.count(
                                          count: unreadCount,
                                          child: Icon(
                                            selected
                                                ? destination.selectedIcon
                                                : destination.icon,
                                            size: 21,
                                          ),
                                        )
                                      : Icon(
                                          selected
                                              ? destination.selectedIcon
                                              : destination.icon,
                                          size: 21,
                                        ),
                                  title: Text(
                                    destination.label,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: selected
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                    ),
                                  ),
                                  onTap: () => onSelected(index),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    const Divider(),
                    Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          _ProfileAvatar(profile: profile, radius: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  profile.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  profile.roleLabel,
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(color: AppColors.textMuted),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: AppColors.success,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Column(
              children: [
                Container(
                  height: 72,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  decoration: const BoxDecoration(
                    color: AppColors.surface,
                    border: Border(bottom: BorderSide(color: AppColors.border)),
                  ),
                  child: Row(
                    children: [
                      Text(
                        destinations[selectedIndex].label,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const Spacer(),
                      if (MediaQuery.sizeOf(context).width >= 1000)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.softGreen,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.calendar_today_outlined,
                                size: 14,
                                color: AppColors.primaryGreen,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _capitalize(date),
                                style: const TextStyle(
                                  color: AppColors.primaryGreen,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(width: 12),
                      _ProfileAvatar(profile: profile, radius: 18),
                    ],
                  ),
                ),
                Expanded(child: body),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({required this.profile, required this.radius});

  final AppUser profile;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.softGreen,
      foregroundColor: AppColors.primaryGreen,
      backgroundImage: profile.photoUrl.isEmpty
          ? null
          : NetworkImage(profile.photoUrl),
      child: profile.photoUrl.isEmpty
          ? Icon(Icons.person_rounded, size: radius)
          : null,
    );
  }
}

String _capitalize(String value) =>
    value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';

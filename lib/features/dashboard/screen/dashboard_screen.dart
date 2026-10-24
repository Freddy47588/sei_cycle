import 'package:flutter/material.dart';
import '../../../core/constants/farm_modules.dart';
import '../../../core/widgets/kebun_sei_logo.dart';
import '../../batches/screen/batch_detail_screen.dart';
import '../../batches/screen/batch_list_screen.dart';
import '../../batches/services/batch_service.dart';
import '../../logbook/screen/logbook_detail_screen.dart';
import '../../logbook/services/logbook_service.dart';
import '../../schedule/screen/schedule_screen.dart';
import '../../sales/screen/sales_screen.dart';
import '../../circular_flow/screen/circular_flow_screen.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/operation_error.dart';
import '../models/dashboard_filter.dart';
import '../widgets/module_monitoring_section.dart';
import 'package:intl/intl.dart';

import '../../../theme/app_theme.dart';
import '../../../core/widgets/async_state_widgets.dart';
import '../../profile/models/app_user.dart';
import '../models/dashboard_summary.dart';
import '../services/dashboard_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    required this.profile,
    this.summaryLoader,
    this.periodSummaryLoader,
    this.productivityLoader,
    this.batchLoader,
    this.onActivity,
    this.onBatchDetail,
    this.onBatches,
    super.key,
  });
  final Future<DashboardSummary> Function({required bool includeFinance})?
  summaryLoader;
  final Future<DashboardSummary> Function(DashboardFilter)? periodSummaryLoader;
  final ProductivityLoader? productivityLoader;
  final MonitoringBatchLoader? batchLoader;
  final void Function(DashboardActivity)? onActivity;
  final void Function(String)? onBatchDetail;
  final VoidCallback? onBatches;
  final AppUser profile;
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  DashboardService? _service;
  late Future<DashboardSummary> _summaryFuture;
  DashboardFilter _filter = DashboardFilter.days(7);
  int _refreshRevision = 0;
  @override
  void initState() {
    super.initState();
    _service =
        widget.summaryLoader == null && widget.periodSummaryLoader == null
        ? DashboardService(profile: widget.profile)
        : null;
    _summaryFuture = _request();
  }

  @override
  void didUpdateWidget(covariant DashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile.uid != widget.profile.uid ||
        oldWidget.profile.role != widget.profile.role ||
        oldWidget.profile.isActive != widget.profile.isActive) {
      _service =
          widget.summaryLoader == null && widget.periodSummaryLoader == null
          ? DashboardService(profile: widget.profile)
          : null;
      _summaryFuture = _request();
      _refreshRevision++;
    }
  }

  Future<DashboardSummary> _request() =>
      widget.periodSummaryLoader?.call(_filter) ??
      widget.summaryLoader?.call(
        includeFinance: widget.profile.canViewFinanceDashboard,
      ) ??
      _service!.getDashboardSummary(
        includeFinance: widget.profile.canViewFinanceDashboard,
        filter: _filter,
      );
  Future<void> _reload() async {
    final future = _request();
    setState(() {
      _summaryFuture = future;
      _refreshRevision++;
    });
    try {
      await future;
    } catch (_) {
      /* FutureBuilder presents the failure. */
    }
  }

  void _period(DashboardFilter filter) {
    setState(() {
      _filter = filter;
      _summaryFuture = _request();
    });
  }

  Future<void> _custom() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(DateTime.now().year + 1, 12, 31),
      initialDateRange: DateTimeRange(
        start: _filter.start,
        end: DateTime(_filter.end.year, _filter.end.month, _filter.end.day - 1),
      ),
    );
    if (!mounted || range == null) return;
    final filter = DashboardFilter(
      start: range.start,
      end: DateTime(range.end.year, range.end.month, range.end.day + 1),
    );
    if (filter.end.difference(filter.start).inDays > 366) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Pilih maksimal 366 hari.')));
      return;
    }
    _period(filter);
  }

  void _openBatch(String id) {
    if (!widget.profile.canViewBatches) return;
    if (widget.onBatchDetail != null) {
      widget.onBatchDetail!(id);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BatchDetailScreen(
          batchId: id,
          service: BatchService(),
          logbookService: LogbookService(),
          userId: widget.profile.uid,
          canManage: widget.profile.canManageBatches,
        ),
      ),
    );
  }

  void _openBatches() {
    if (!widget.profile.canViewBatches) return;
    if (widget.onBatches != null) {
      widget.onBatches!();
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BatchListScreen(
          service: BatchService(),
          logbookService: LogbookService(),
          userId: widget.profile.uid,
          canManage: widget.profile.canManageBatches,
        ),
      ),
    );
  }

  void _openActivity(DashboardActivity activity) {
    if (widget.onActivity != null) {
      widget.onActivity!(activity);
      return;
    }
    if (activity.source == 'schedule') {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ScheduleScreen(profile: widget.profile),
        ),
      );
    } else if (widget.profile.canViewLogbooks) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => LogbookDetailScreen(
            service: LogbookService(),
            entryId: activity.id,
            userId: widget.profile.uid,
            canEdit: widget.profile.canManageLogbooks,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: _reload,
    child: SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _WelcomeHeader(), const SizedBox(height: 20),
          Text(
            'Periode analitik',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final days in [1, 7, 30, 90])
                ChoiceChip(
                  label: Text(
                    days == 1 ? 'Hari Ini' : '$days Hari Terakhir',
                    style: TextStyle(
                      color:
                          _filter.start == DashboardFilter.days(days).start &&
                              _filter.end == DashboardFilter.days(days).end
                          ? Colors.white
                          : null,
                    ),
                  ),
                  selected:
                      _filter.start == DashboardFilter.days(days).start &&
                      _filter.end == DashboardFilter.days(days).end,
                  onSelected: (_) => _period(DashboardFilter.days(days)),
                ),
              ActionChip(
                label: const Text('Rentang Custom'),
                onPressed: _custom,
              ),
              ActionChip(
                avatar: const Icon(Icons.refresh, size: 16),
                label: const Text('Refresh'),
                onPressed: _reload,
              ),
            ],
          ),
          Text(_filter.label), const SizedBox(height: 20),
          // A new key discards retained FutureBuilder data, including old finance periods.
          FutureBuilder<DashboardSummary>(
            key: ObjectKey(_summaryFuture),
            future: _summaryFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Column(
                  children: [
                    _HeaderLiveBadge(
                      label: 'Memuat',
                      color: AppColors.textMuted,
                    ),
                    LoadingState(label: 'Memuat ringkasan...'),
                  ],
                );
              }
              if (snapshot.hasError) {
                return Column(
                  children: [
                    const _HeaderLiveBadge(
                      label: 'Gagal',
                      color: AppColors.error,
                    ),
                    ErrorState(
                      message: dashboardError(snapshot.error),
                      onRetry: _reload,
                    ),
                  ],
                );
              }
              final summary = snapshot.requireData;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SectionHeader(
                    title: 'Ringkasan Operasional',
                    subtitle: 'KPI hari ini & kondisi saat ini',
                    trailing: _HeaderLiveBadge(
                      label: summary.sectionErrors.isEmpty
                          ? 'Dimuat'
                          : 'Sebagian',
                      color: AppColors.primaryGreen,
                    ),
                  ),
                  if (summary.updatedAt != null)
                    Text(
                      'Terakhir diperbarui: ${DateFormat('d MMM yyyy HH:mm:ss', 'id_ID').format(summary.updatedAt!)}',
                    ),
                  const SizedBox(height: 12),
                  for (final entry in summary.sectionErrors.entries)
                    if (!['finance', 'sales'].contains(entry.key))
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${dashboardSectionLabel(entry.key)} ? Belum dapat dihitung',
                              ),
                              Text(dashboardError(entry.value)),
                              TextButton.icon(
                                onPressed: _reload,
                                icon: const Icon(Icons.refresh),
                                label: const Text('Coba lagi'),
                              ),
                            ],
                          ),
                        ),
                      ),
                  _StatsGrid(
                    summary: summary,
                    onBatches: widget.profile.canViewBatches
                        ? _openBatches
                        : null,
                  ),
                  if (summary.inventoryTruncated)
                    Text(
                      'Stok Saat Ini: cakupan ${summary.inventoryLoaded} item pertama berdasarkan ID; bukan jumlah global.',
                    ),
                  if (summary.lowStockPreview.isNotEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Perlu perhatian - Saat Ini',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            for (final item in summary.lowStockPreview)
                              Text(
                                '${item.name}: ${item.currentStock} ${item.unit} - ${item.currentStock <= 0 ? 'Habis' : 'Rendah'} (minimum ${item.minStock})',
                              ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 24),
                  const SectionHeader(
                    title: 'Sistem Aliran Nutrisi',
                    subtitle: 'Diagram konsep dan catatan aliran aktual',
                  ),
                  if (!summary.sectionErrors.containsKey('flows'))
                    NutrientFlowCard(flows: summary.circularFlows),
                  TextButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => Scaffold(
                          appBar: AppBar(title: const Text('Aliran Nutrisi')),
                          body: CircularFlowScreen(profile: widget.profile),
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.recycling),
                    label: const Text('Lihat Aliran Aktual'),
                  ),
                  if (widget.profile.canViewSales)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Penjualan Periode Terpilih',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            if (summary.salesError != null)
                              Text(operationError(summary.salesError!))
                            else if (summary.salesTotal != null) ...[
                              Text(currencyFormat.format(summary.salesTotal)),
                              if (summary.soldQuantities.isEmpty)
                                const Text('Belum ada penjualan.'),
                              for (final entry
                                  in summary.soldQuantities.entries)
                                Text('${entry.key}: ${entry.value}'),
                            ],
                            const Text(
                              'Pemasukan lengkap tetap berasal dari catatan Keuangan.',
                            ),
                            TextButton(
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute<void>(
                                  builder: (_) => Scaffold(
                                    appBar: AppBar(
                                      title: const Text('Penjualan'),
                                    ),
                                    body: SalesScreen(profile: widget.profile),
                                  ),
                                ),
                              ),
                              child: const Text('Lihat Penjualan'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  Text(
                    'Pratinjau maksimal 5 aliran terbaru - ${_filter.label}',
                  ),
                  const SizedBox(height: 24),
                  const SectionHeader(
                    title: 'Aktivitas Hari Ini',
                    subtitle:
                        'Jadwal hari ini, logbook terbaru & checklist selesai - maksimal 10 entri',
                  ),
                  if (summary.sectionErrors.containsKey('activities'))
                    const Text(
                      'Aktivitas belum dapat dimuat. Gunakan Coba lagi di atas.',
                    )
                  else if (summary.recentActivities.isEmpty)
                    const EmptyState(
                      title: 'Belum ada aktivitas hari ini',
                      message:
                          'Catatan logbook dan jadwal akan muncul setelah tersedia.',
                      icon: Icons.event_note_outlined,
                    )
                  else
                    _ActivityTimeline(
                      activities: summary.recentActivities,
                      onActivity: _openActivity,
                      onBatch: _openBatch,
                    ),
                  if (widget.profile.canViewFinanceDashboard &&
                      summary.financeVisible) ...[
                    const SizedBox(height: 24),
                    _RevenueCard(
                      summary: summary,
                      period: _filter.label,
                      onRetry: _reload,
                    ),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          ModuleMonitoringSection(
            filter: _filter,
            refreshRevision: _refreshRevision,
            loader: widget.productivityLoader,
            batchLoader: widget.batchLoader,
            offline:
                widget.summaryLoader != null ||
                widget.periodSummaryLoader != null,
            onBatchDetail: _openBatch,
          ),
          const SizedBox(height: 20),
        ],
      ),
    ),
  );
}

String dashboardSectionLabel(String key) => switch (key) {
  'modules' => 'Modul aktif',
  'logs' => 'Logbook hari ini',
  'schedules' => 'Jadwal hari ini',
  'batches' => 'Batch',
  'inventory' => 'Stok',
  'activities' => 'Aktivitas terbaru',
  'flows' => 'Aliran aktual',
  _ => 'Ringkasan',
};

String dashboardError(Object? error) => dashboardLoadError(error);

class _WelcomeHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 560;
      final logoSize = compact
          ? constraints.maxWidth < 330
                ? 76.0
                : 88.0
          : 112.0;
      final heading = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Selamat Datang!',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Dashboard SeiCycle',
            style: TextStyle(
              color: Colors.white,
              fontSize: compact ? 22 : 26,
              fontWeight: FontWeight.bold,
              letterSpacing: 0,
            ),
          ),
        ],
      );
      const details = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Kebun Sei - Sistem Pertanian & Peternakan Terintegrasi Berbasis Nutrisi Berkelanjutan',
            style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
          ),
          SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _HeaderBadge(
                icon: Icons.location_on_outlined,
                label: 'Pakisaji, Malang',
              ),
              _HeaderBadge(icon: Icons.area_chart_outlined, label: '+/-500 m2'),
            ],
          ),
        ],
      );
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.primaryGreen, AppColors.primaryGreenLight],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryGreen.withValues(alpha: 0.3),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: heading),
                      const SizedBox(width: 12),
                      KebunSeiLogo(size: logoSize),
                    ],
                  ),
                  const SizedBox(height: 12),
                  details,
                ],
              )
            : Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [heading, const SizedBox(height: 4), details],
                    ),
                  ),
                  const SizedBox(width: 20),
                  KebunSeiLogo(size: logoSize),
                ],
              ),
      );
    },
  );
}

class _HeaderBadge extends StatelessWidget {
  const _HeaderBadge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 13),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderLiveBadge extends StatelessWidget {
  const _HeaderLiveBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(label),
      avatar: Icon(Icons.circle, color: color, size: 10),
      backgroundColor: color.withValues(alpha: 0.1),
      labelStyle: TextStyle(
        fontFamily: AppTypography.family,
        color: color,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
      side: BorderSide.none,
      padding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    required this.title,
    required this.subtitle,
    this.trailing,
    super.key,
  });

  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: AppColors.textDark,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 12), trailing!],
        ],
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.summary, this.onBatches});
  final VoidCallback? onBatches;

  final DashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    final stats = [
      _StatData(
        title: 'Modul Aktif',
        value: summary.activeModuleCount?.toString() ?? 'Belum dapat dihitung',
        helper: 'Saat Ini - modul budidaya aktif',
        icon: Icons.hub_outlined,
        color: AppColors.primaryGreen,
      ),
      _StatData(
        title: 'Aktivitas Hari Ini',
        value: summary.todayLogCount?.toString() ?? 'Belum dapat dihitung',
        helper: 'Hari Ini - catatan logbook',
        icon: Icons.edit_note_outlined,
        color: AppColors.warning,
      ),
      _StatData(
        title: 'Stok Rendah',
        value: summary.lowStockCount?.toString() ?? 'Belum dapat dihitung',
        helper:
            'Saat Ini - ${summary.inventoryTruncated ? 'cakupan terbatas' : 'seluruh item'}',
        icon: Icons.inventory_2_outlined,
        color: AppColors.error,
      ),
      _StatData(
        title: 'Jadwal Hari Ini',
        value: summary.todayScheduleCount?.toString() ?? 'Belum dapat dihitung',
        helper:
            'Hari Ini - ${summary.pendingScheduleCount ?? '?'} pending / ${summary.doneScheduleCount ?? '?'} done / ${summary.skippedScheduleCount ?? '?'} skipped',
        icon: Icons.event_note_outlined,
        color: AppColors.info,
      ),
      _StatData(
        title: 'Batch Aktif',
        value: summary.activeBatchCount?.toString() ?? 'Belum dapat dihitung',
        helper:
            'Saat Ini - ${summary.completedBatchCount ?? '?'} batch completed',
        icon: Icons.layers_outlined,
        color: AppColors.primaryGreen,
        onTap: onBatches,
      ),
      _StatData(
        title: 'Stok Habis',
        value: summary.outOfStockCount?.toString() ?? 'Belum dapat dihitung',
        helper:
            'Saat Ini - saldo <= 0${summary.inventoryTruncated ? ' - cakupan terbatas' : ''}',
        icon: Icons.production_quantity_limits,
        color: AppColors.accentBrown,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900
            ? 4
            : constraints.maxWidth < 340
            ? 1
            : 2;
        final scale = MediaQuery.textScalerOf(context).scale(1);
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            mainAxisExtent: 190 + (scale - 1) * 150,
          ),
          itemCount: stats.length,
          itemBuilder: (context, i) => InkWell(
            onTap: stats[i].onTap,
            borderRadius: BorderRadius.circular(16),
            child: _StatCard(data: stats[i]),
          ),
        );
      },
    );
  }
}

class _StatData {
  const _StatData({
    required this.title,
    required this.value,
    required this.helper,
    required this.icon,
    required this.color,
    this.onTap,
  });

  final VoidCallback? onTap;
  final String title;
  final String value;
  final String helper;
  final IconData icon;
  final Color color;
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.data});

  final _StatData data;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: data.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(data.icon, color: data.color, size: 20),
            ),
            const Spacer(),
            Text(
              data.value,
              style:
                  (data.value == 'Belum dapat dihitung'
                          ? Theme.of(context).textTheme.titleMedium
                          : Theme.of(context).textTheme.headlineMedium)
                      ?.copyWith(
                        color: data.color,
                        fontWeight: FontWeight.bold,
                      ),
            ),
            const SizedBox(height: 3),
            Text(
              data.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textDark,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              data.helper,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class NutrientFlowCard extends StatelessWidget {
  const NutrientFlowCard({required this.flows, super.key});

  final List<DashboardCircularFlow> flows;

  @override
  Widget build(BuildContext context) {
    final nodes = _flowNodes(const []);
    final description = flows.isEmpty
        ? 'Ilustrasi siklus nutrisi; belum ada catatan aliran. Setiap limbah menjadi sumber daya baru: kotoran dan sisa organik diolah maggot/cacing, lalu kembali menjadi pakan, kascing, dan nutrisi tanaman.'
        : 'Diagram merupakan ilustrasi. Catatan aktual ditampilkan terpisah di bawah.';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ilustrasi Siklus Nutrisi Kebun Sei',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(color: AppColors.primaryGreen),
            ),
            const SizedBox(height: 16),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var index = 0; index < nodes.length; index++) ...[
                    _FlowChip(node: nodes[index]),
                    if (index < nodes.length - 1)
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Icon(
                          Icons.chevron_right_rounded,
                          color: AppColors.textMuted,
                        ),
                      ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text(
              description,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
            ),
            if (flows.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'Aliran Aktual',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              for (final flow in flows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    '${flow.materialName} - ${flow.quantity} ${flow.unit}\n${FarmModules.nameOf(flow.sourceModuleType)} -> ${FarmModules.nameOf(flow.destinationModuleType)}\n${flow.flowDate == null ? 'Tanggal tidak tersedia' : DateFormat('d MMM yyyy', 'id_ID').format(flow.flowDate!)}',
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

List<_FlowNode> _flowNodes(List<DashboardCircularFlow> flows) {
  if (flows.isEmpty) {
    return const [
      _FlowNode(
        'Limbah Dapur',
        Icons.recycling_outlined,
        AppColors.accentBrown,
      ),
      _FlowNode(
        'Maggot BSF',
        Icons.bug_report_outlined,
        AppColors.accentLightGreen,
      ),
      _FlowNode('Pakan Lele', Icons.set_meal_outlined, AppColors.info),
      _FlowNode('Air Kolam', Icons.water_drop_outlined, Color(0xFF06B6D4)),
      _FlowNode(
        'Cacing & Kascing',
        Icons.grass_outlined,
        AppColors.primaryGreen,
      ),
      _FlowNode('Tanaman Pangan', Icons.eco_outlined, AppColors.success),
    ];
  }

  final nodes = <_FlowNode>[];
  void add(String moduleType) {
    if (nodes.any((node) => node.moduleType == moduleType)) return;
    nodes.add(_FlowNode.fromModule(moduleType));
  }

  for (final flow in flows) {
    add(flow.sourceModuleType);
    add(flow.destinationModuleType);
  }
  return nodes;
}

class _FlowNode {
  const _FlowNode(this.label, this.icon, this.color, [this.moduleType = '']);

  factory _FlowNode.fromModule(String moduleType) {
    return switch (moduleType) {
      'ayam_kampung' => const _FlowNode(
        'Ayam',
        Icons.egg_alt_outlined,
        AppColors.warning,
        'ayam_kampung',
      ),
      'maggot_bsf' => const _FlowNode(
        'Maggot',
        Icons.bug_report_outlined,
        AppColors.accentLightGreen,
        'maggot_bsf',
      ),
      'cacing_tanah' => const _FlowNode(
        'Cacing',
        Icons.grass_outlined,
        AppColors.primaryGreen,
        'cacing_tanah',
      ),
      'lele' => const _FlowNode(
        'Lele',
        Icons.water_drop_outlined,
        AppColors.info,
        'lele',
      ),
      'tanaman' => const _FlowNode(
        'Tanaman',
        Icons.eco_outlined,
        AppColors.success,
        'tanaman',
      ),
      _ => _FlowNode(
        moduleType.isEmpty ? 'Aliran' : moduleType,
        Icons.recycling_outlined,
        AppColors.accentBrown,
        moduleType,
      ),
    };
  }

  final String label;
  final IconData icon;
  final Color color;
  final String moduleType;
}

class _FlowChip extends StatelessWidget {
  const _FlowChip({required this.node});

  final _FlowNode node;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 78,
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: node.color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(node.icon, color: node.color, size: 25),
          ),
          const SizedBox(height: 7),
          Text(
            node.label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textMedium,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityTimeline extends StatelessWidget {
  const _ActivityTimeline({
    required this.activities,
    required this.onActivity,
    required this.onBatch,
  });
  final List<DashboardActivity> activities;
  final void Function(DashboardActivity) onActivity;
  final void Function(String) onBatch;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          for (final activity in activities)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(activity.icon, color: activity.color),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        InkWell(
                          onTap: () => onActivity(activity),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Text(
                              activity.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        Text(
                          '${activity.time} - ${FarmModules.nameOf(activity.moduleType)}',
                        ),
                        Text(switch (activity.status) {
                          'done' => 'Selesai',
                          'pending' => 'Belum selesai',
                          'skipped' => 'Dilewati',
                          'recorded' => 'Tercatat',
                          _ => 'Status tidak dikenal',
                        }),
                        if (activity.batchId != null)
                          TextButton(
                            onPressed: () => onBatch(activity.batchId!),
                            child: Text('Batch ${activity.batchId}'),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}

class _RevenueCard extends StatelessWidget {
  const _RevenueCard({
    required this.summary,
    required this.period,
    required this.onRetry,
  });
  final DashboardSummary summary;
  final String period;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ringkasan Arus Kas',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(color: AppColors.primaryGreen),
          ),
          Text(period),
          const SizedBox(height: 12),
          if (summary.financeError != null)
            ErrorState(
              message: dashboardError(summary.financeError),
              onRetry: onRetry,
            )
          else ...[
            if (!summary.hasFinanceData)
              const Text('Belum ada transaksi keuangan pada periode ini.'),
            for (final row in [
              ('Pemasukan', summary.monthlyIncome, AppColors.success),
              ('Pengeluaran', summary.monthlyExpense, AppColors.error),
              (
                'Arus Kas Bersih',
                summary.monthlyProfit,
                AppColors.primaryGreen,
              ),
            ])
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  alignment: WrapAlignment.spaceBetween,
                  children: [
                    Text(row.$1),
                    Text(
                      row.$2 == null
                          ? 'Belum dapat dihitung'
                          : NumberFormat.currency(
                              locale: 'id_ID',
                              symbol: 'Rp ',
                              decimalDigits: 0,
                            ).format(row.$2),
                      style: TextStyle(
                        color: row.$3,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            const Text(
              'Arus kas bersih = pemasukan - pengeluaran. Bukan laba akuntansi lengkap.',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ],
        ],
      ),
    ),
  );
}

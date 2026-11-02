import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/excel_generator.dart';
import '../../../core/utils/operation_error.dart';
import '../../../core/utils/pdf_generator.dart';
import '../../../core/widgets/app_ui.dart';
import '../../../core/widgets/async_state_widgets.dart';
import '../../../core/widgets/feature_page.dart';
import '../../../theme/app_theme.dart';
import '../../profile/models/app_user.dart';
import '../models/analytics_model.dart';
import '../models/report_filter.dart';
import '../services/report_service.dart';

class ReportScreen extends StatefulWidget {
  const ReportScreen({required this.profile, this.service, super.key});

  final AppUser profile;
  final ReportService? service;

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  late final ReportService _service;
  late Future<AnalyticsModel> _dataFuture;
  late ReportFilter _filter;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? ReportService();

    // Default filter: last 30 days, full summary
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    _filter = ReportFilter(
      startDate: DateTime(today.year, today.month, today.day - 29),
      endDate: today,
      reportType: widget.profile.canViewFinance
          ? ReportType.fullSummary
          : ReportType.operational,
    );
    _load();
  }

  void _load() {
    setState(() {
      _dataFuture = _service.generateReport(
        _filter,
        includeFinance: widget.profile.canViewFinanceDashboard,
        profile: widget.profile,
      );
    });
  }

  void _exportPdf(AnalyticsModel data) async {
    try {
      await PdfGenerator.generateAndSharePdf(data);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(operationError(e))));
      }
    }
  }

  void _exportExcel(AnalyticsModel data) async {
    try {
      await ExcelGenerator.generateAndShareExcel(data);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(operationError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FeaturePage(
      title: 'Laporan',
      subtitle: 'Rekap operasional, inventaris, dan keuangan Kebun Sei.',
      actions: [
        OutlinedButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Refresh'),
        ),
      ],
      child: Column(
        children: [
          _buildFilters(),
          const SizedBox(height: 14),
          Expanded(
            child: FutureBuilder<AnalyticsModel>(
              key: ObjectKey(_dataFuture),
              future: _dataFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const LoadingState(label: 'Memuat data laporan...');
                }
                if (snapshot.hasError) {
                  return ErrorState(
                    message: operationError(snapshot.error!),
                    onRetry: _load,
                  );
                }

                final data = snapshot.requireData;
                return _buildContent(data);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return AppCard(
      padding: const EdgeInsets.all(12),
      child: ResponsiveFormRow(
        breakpoint: 680,
        children: [
          _DateRangePicker(
            startDate: _filter.startDate,
            endDate: _filter.endDate,
            onChanged: (start, end) {
              _filter = _filter.copyWith(startDate: start, endDate: end);
              _load();
            },
          ),
          DropdownButtonFormField<ReportType>(
            isExpanded: true,
            initialValue: _filter.reportType,
            decoration: const InputDecoration(
              labelText: 'Jenis laporan',
              prefixIcon: Icon(Icons.tune_rounded),
            ),
            items: [
              for (final type in ReportType.values.where(
                (type) =>
                    widget.profile.canViewFinance ||
                    type == ReportType.operational ||
                    type == ReportType.inventory,
              ))
                DropdownMenuItem(
                  value: type,
                  child: Text(
                    _reportTypeLabel(type),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (val) {
              if (val != null) {
                _filter = _filter.copyWith(reportType: val);
                _load();
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildContent(AnalyticsModel data) {
    final currencyFormat = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp',
      decimalDigits: 0,
    );

    final hasReportData =
        data.logbooks.isNotEmpty ||
        data.inventoryItems.isNotEmpty ||
        data.totalIncome > 0 ||
        data.totalExpense > 0 ||
        data.sales.isNotEmpty ||
        data.circularFlows.isNotEmpty;

    return ListView(
      padding: const EdgeInsets.only(bottom: 12),
      children: [
        if (!hasReportData) ...[
          const InlineMessage(
            icon: Icons.analytics_outlined,
            color: AppColors.info,
            message:
                'Laporan akan tersedia setelah data logbook, inventaris, atau transaksi terkumpul.',
          ),
          const SizedBox(height: 12),
        ],
        ResponsiveFormRow(
          breakpoint: 520,
          children: [
            FilledButton.icon(
              onPressed: () => _exportPdf(data),
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('Export PDF'),
              style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            ),
            FilledButton.icon(
              onPressed: () => _exportExcel(data),
              icon: const Icon(Icons.table_chart_outlined),
              label: const Text('Export Excel'),
              style: FilledButton.styleFrom(backgroundColor: AppColors.success),
            ),
          ],
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 860
                ? 3
                : constraints.maxWidth >= 560
                ? 2
                : 1;
            const spacing = 12.0;
            final width =
                (constraints.maxWidth - ((columns - 1) * spacing)) / columns;
            final metrics = [
              _ReportMetric(
                label: 'Aktivitas logbook',
                value: '${data.logbooks.length}',
                helper: 'Catatan pada rentang laporan',
                icon: Icons.menu_book_outlined,
                color: AppColors.primaryGreen,
              ),
              _ReportMetric(
                label: 'Item stok rendah',
                value: '${data.lowStockItems.length}',
                helper: data.lowStockItems.isEmpty
                    ? 'Tidak ada stok kritis'
                    : 'Perlu ditindaklanjuti',
                icon: data.lowStockItems.isEmpty
                    ? Icons.check_circle_outline
                    : Icons.warning_amber_rounded,
                color: data.lowStockItems.isEmpty
                    ? AppColors.success
                    : AppColors.warning,
              ),
              if (data.financeIncluded)
                _ReportMetric(
                  label: 'Total pemasukan',
                  value: currencyFormat.format(data.totalIncome),
                  helper: 'Akumulasi transaksi income',
                  icon: Icons.south_west_rounded,
                  color: AppColors.success,
                ),
              if (data.financeIncluded)
                _ReportMetric(
                  label: 'Total pengeluaran',
                  value: currencyFormat.format(data.totalExpense),
                  helper: 'Akumulasi transaksi expense',
                  icon: Icons.north_east_rounded,
                  color: AppColors.error,
                ),
              if (data.financeIncluded)
                _ReportMetric(
                  label: 'Arus Kas Bersih',
                  value: currencyFormat.format(data.profitLoss),
                  helper: data.profitLoss >= 0
                      ? 'Arus kas positif'
                      : 'Pengeluaran lebih besar',
                  icon: Icons.account_balance_wallet_outlined,
                  color: data.profitLoss >= 0
                      ? AppColors.primaryGreen
                      : AppColors.warning,
                ),
            ];
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (final metric in metrics)
                  SizedBox(width: width, child: _ReportMetricCard(metric)),
              ],
            );
          },
        ),
        if (data.financeIncluded)
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Penjualan periode: ${currencyFormat.format(data.totalSales)}',
                ),
                const Text('Penjualan per produk'),
                for (final e in data.salesPerProduct.entries)
                  Text('${e.key}: ${currencyFormat.format(e.value)}'),
                const Text('Penjualan per modul'),
                for (final e in data.salesPerModule.entries)
                  Text('${e.key}: ${currencyFormat.format(e.value)}'),
                const Text(
                  'Pemasukan dihitung dari Keuangan; total penjualan tidak ditambahkan lagi.',
                ),
              ],
            ),
          ),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Aliran nutrisi aktual'),
              if (data.circularFlows.isEmpty)
                const Text(
                  'Belum ada catatan aliran aktual pada cakupan laporan.',
                ),
              for (final e in data.flowsPerMaterial.entries)
                Text('${e.key}: ${e.value}'),
            ],
          ),
        ),
        const SizedBox(height: 14),
        InlineMessage(
          icon: Icons.info_outline,
          color: AppColors.info,
          message:
              'Periode laporan: ${_formatDate(_filter.startDate)} sampai ${_formatDate(_filter.endDate)}.',
        ),
      ],
    );
  }
}

class _ReportMetric {
  const _ReportMetric({
    required this.label,
    required this.value,
    required this.helper,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final String helper;
  final IconData icon;
  final Color color;
}

class _ReportMetricCard extends StatelessWidget {
  const _ReportMetricCard(this.metric);

  final _ReportMetric metric;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppIconBox(icon: metric.icon, color: metric.color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  metric.label,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    metric.value,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: metric.color,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  metric.helper,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: AppColors.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DateRangePicker extends StatelessWidget {
  const _DateRangePicker({
    required this.startDate,
    required this.endDate,
    required this.onChanged,
  });

  final DateTime startDate;
  final DateTime endDate;
  final void Function(DateTime, DateTime) onChanged;

  @override
  Widget build(BuildContext context) {
    final format = DateFormat('dd MMM yyyy');
    return OutlinedButton.icon(
      onPressed: () async {
        final result = await showDateRangePicker(
          context: context,
          firstDate: DateTime(2020),
          lastDate: DateTime.now(),
          initialDateRange: DateTimeRange(start: startDate, end: endDate),
        );
        if (result != null) {
          onChanged(result.start, result.end);
        }
      },
      icon: const Icon(Icons.date_range),
      label: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text('${format.format(startDate)} - ${format.format(endDate)}'),
      ),
    );
  }
}

String _reportTypeLabel(ReportType type) => switch (type) {
  ReportType.operational => 'Operasional',
  ReportType.finance => 'Keuangan',
  ReportType.inventory => 'Inventaris',
  ReportType.fullSummary => 'Ringkasan lengkap',
};

String _formatDate(DateTime date) => DateFormat('dd MMM yyyy').format(date);

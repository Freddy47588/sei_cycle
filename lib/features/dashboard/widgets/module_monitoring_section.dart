import '../../../core/utils/operation_error.dart';
import '../../../core/utils/debug_diagnostics.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/farm_modules.dart';
import '../../../core/widgets/async_state_widgets.dart';
import '../../batches/models/cultivation_batch.dart';
import '../../batches/services/batch_service.dart';
import '../models/dashboard_filter.dart';
import '../models/productivity_point.dart';
import '../services/productivity_service.dart';
import 'productivity_chart.dart';

typedef ProductivityLoader =
    Future<ProductivityReport> Function(
      DashboardFilter filter,
      String module,
      String? batchId,
    );
typedef MonitoringBatchLoader =
    Future<BatchPage> Function(String module, BatchPage? previous);

class ModuleMonitoringSection extends StatefulWidget {
  const ModuleMonitoringSection({
    required this.filter,
    required this.onBatchDetail,
    this.loader,
    this.batchLoader,
    this.offline = false,
    this.refreshRevision = 0,
    super.key,
  });
  final DashboardFilter filter;
  final ProductivityLoader? loader;
  final MonitoringBatchLoader? batchLoader;
  final bool offline;
  final int refreshRevision;
  final void Function(String) onBatchDetail;
  @override
  State<ModuleMonitoringSection> createState() =>
      _ModuleMonitoringSectionState();
}

class _ModuleMonitoringSectionState extends State<ModuleMonitoringSection> {
  late final ProductivityLoader _load;
  late final MonitoringBatchLoader _loadBatches;
  String _module = FarmModules.ayamKampung.id;
  CultivationBatch? _batch;
  final List<CultivationBatch> _batches = [];
  BatchPage? _page;
  ProductivityReport? _report;
  Object? _error, _batchError;
  bool _loading = true, _batchLoading = true;
  int _generation = 0, _batchGeneration = 0, _seriesIndex = 0;
  @override
  void initState() {
    super.initState();
    _load =
        widget.loader ??
        (widget.offline
            ? (_, _, _) async => const ProductivityReport()
            : ProductivityService().load);
    _loadBatches =
        widget.batchLoader ??
        (widget.offline
            ? (_, _) async => const BatchPage(entries: [], hasMore: false)
            : (module, previous) => BatchService().getPage(
                moduleType: module,
                cursor: previous?.cursor,
              ));
    _reload();
    _fetchBatches();
  }

  @override
  void didUpdateWidget(covariant ModuleMonitoringSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filter != widget.filter ||
        oldWidget.refreshRevision != widget.refreshRevision) {
      if (oldWidget.refreshRevision != widget.refreshRevision) {
        _batchGeneration++;
        _page = null;
        _batches.clear();
        _batch = null;
        _fetchBatches();
      }
      _reload();
    }
  }

  Future<void> _reload() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      _report = null;
      _seriesIndex = 0;
    });
    try {
      final value = await _load(widget.filter, _module, _batch?.id);
      if (!mounted || generation != _generation) return;
      setState(() {
        _report = value;
        _loading = false;
      });
    } catch (error, stack) {
      logLoadFailure('ProductivityService', 'load', error, stack);
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _fetchBatches() async {
    final generation = ++_batchGeneration;
    setState(() {
      _batchLoading = true;
      _batchError = null;
    });
    try {
      final page = await _loadBatches(_module, _page);
      if (!mounted || generation != _batchGeneration) return;
      setState(() {
        _page = page;
        _batchLoading = false;
        for (final batch in page.entries) {
          if (!_batches.any((b) => b.id == batch.id)) _batches.add(batch);
        }
      });
    } catch (error) {
      if (!mounted || generation != _batchGeneration) return;
      setState(() {
        _batchError = error;
        _batchLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Monitoring Produktivitas Budidaya',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(widget.filter.label),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final module in FarmModules.values)
                  ChoiceChip(
                    label: Text(
                      module.name,
                      style: TextStyle(
                        color: _module == module.id ? Colors.white : null,
                      ),
                    ),
                    selected: _module == module.id,
                    onSelected: (_) {
                      if (_module == module.id) return;
                      setState(() {
                        _module = module.id;
                        _batch = null;
                        _batches.clear();
                        _page = null;
                      });
                      _reload();
                      _fetchBatches();
                    },
                  ),
              ],
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              key: ValueKey('batch-$_module-${_batch?.id}-${_batches.length}'),
              initialValue: _batch?.id ?? '',
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Batch monitoring'),
              items: [
                const DropdownMenuItem(
                  value: '',
                  child: Text(
                    'Semua / tanpa batch',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                for (final b in _batches)
                  DropdownMenuItem(
                    value: b.id,
                    child: Text(
                      '${b.input.name} · ${batchStatusLabel(b.status)}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (id) {
                setState(
                  () => _batch = _batches.where((b) => b.id == id).firstOrNull,
                );
                _reload();
              },
            ),
            if (_batch == null)
              const Text('Mencakup semua batch dan catatan tanpa batch.'),
            if (_batchLoading) const LinearProgressIndicator(),
            if (_batchError != null)
              ErrorState(
                message: 'Daftar batch gagal dimuat.',
                onRetry: _fetchBatches,
              ),
            if (_page?.hasMore ?? false)
              TextButton(
                onPressed: _batchLoading ? null : _fetchBatches,
                child: Text('Muat batch lainnya (${_batches.length} dimuat)'),
              ),
            if (_batch case final batch?) ...[
              const SizedBox(height: 8),
              Text(
                'Status: ${batchStatusLabel(batch.status)} · ${batch.input.commodity}',
              ),
              Text(
                'Estimasi panen: ${batch.input.expectedHarvestAt == null ? 'Belum tersedia' : DateFormat('d MMM yyyy', 'id_ID').format(batch.input.expectedHarvestAt!)}',
              ),
              TextButton(
                onPressed: () => widget.onBatchDetail(batch.id),
                child: const Text('Lihat Detail Batch'),
              ),
            ],
            const SizedBox(height: 16),
            if (_loading)
              const LoadingState(label: 'Memuat pengamatan dan produksi...')
            else if (_error != null)
              ErrorState(message: dashboardLoadError(_error), onRetry: _reload)
            else if (report != null) ...[
              if (report.samplesExcluded)
                const Text(
                  'Data bertanda sampel tidak disertakan dalam produktivitas.',
                ),
              Text(
                '${report.logCount} catatan ${report.logsTruncated ? 'terbaru (batas 500; bukan total periode)' : 'pada periode ini'}',
              ),
              if (report.lastActivity != null)
                Text(
                  'Aktivitas terakhir dalam periode: ${DateFormat('d MMM yyyy HH:mm', 'id_ID').format(report.lastActivity!)}',
                ),
              if (report.logsTruncated)
                const Text(
                  'Grafik hanya mencakup 500 catatan terbaru. Persempit periode atau pilih batch.',
                ),
              const SizedBox(height: 12),
              if (report.series.isEmpty)
                const Text('Belum ada data produktivitas pada periode ini.')
              else ...[
                DropdownButtonFormField<int>(
                  key: ValueKey('series-$_generation-$_seriesIndex'),
                  initialValue: _seriesIndex,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Metrik & kelompok pengamatan',
                  ),
                  items: [
                    for (var i = 0; i < report.series.length; i++)
                      DropdownMenuItem(
                        value: i,
                        child: Text(
                          '${report.series[i].label} (${report.series[i].unit})',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (i) {
                    if (i != null) setState(() => _seriesIndex = i);
                  },
                ),
                const SizedBox(height: 16),
                ProductivityChart(
                  series: report.series[_seriesIndex],
                  filter: widget.filter,
                ),
              ],
              const SizedBox(height: 18),
              Text(
                'Hasil produksi aktual',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (report.productionUncertain)
                const Text('Data produksi belum dapat dihitung secara akurat.')
              else if (report.production.isEmpty)
                const Text(
                  'Belum ada hasil produksi aktual terverifikasi pada periode ini.',
                )
              else
                for (final item in report.production.entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      '${item.key}: ${NumberFormat.decimalPattern('id_ID').format(item.value)}',
                    ),
                  ),
            ],
          ],
        ),
      ),
    );
  }
}

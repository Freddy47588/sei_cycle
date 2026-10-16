import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/farm_modules.dart';
import '../../../theme/app_theme.dart';
import '../models/logbook_entry.dart';
import '../models/logbook_form_spec.dart';
import '../models/logbook_page.dart';
import '../services/logbook_service.dart';
import 'logbook_detail_screen.dart';

class LogbookListScreen extends StatefulWidget {
  const LogbookListScreen({
    required this.service,
    required this.userId,
    required this.canEdit,
    this.initialModuleId,
    super.key,
  });
  final LogbookService service;
  final String userId;
  final bool canEdit;
  final String? initialModuleId;
  @override
  State<LogbookListScreen> createState() => _LogbookListScreenState();
}

class _LogbookListScreenState extends State<LogbookListScreen> {
  late String? _module = widget.initialModuleId;
  String _period = 'Semua tanggal';
  int _periodRevision = 0;
  bool _newest = true;
  DateTimeRange? _range;
  Timer? _debounce;
  String _search = '';
  List<LogbookEntry> _entries = [];
  LogbookPage? _page;
  bool _loading = true;
  Object? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (!reset && (_loading || _page?.hasMore != true)) return;
    final generation = reset ? ++_generation : _generation;
    final filter = LogbookFilter.forPeriod(
      moduleId: _module,
      period: _period,
      now: DateTime.now(),
      customStart: _range?.start,
      customEnd: _range?.end,
      newestFirst: _newest,
    );
    final cursor = reset ? null : _page?.cursor;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _entries = [];
        _page = null;
      }
    });
    try {
      final page = await widget.service.getPage(filter: filter, cursor: cursor);
      if (!mounted || generation != _generation) return;
      setState(() {
        _entries = mergeLogbookPages(_entries, page.entries);
        _page = page;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() => _error = error);
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _setPeriod(String value) async {
    if (value == 'Rentang tanggal') {
      final range = await showDateRangePicker(
        cancelText: 'Batal',
        saveText: 'Terapkan',
        helpText: 'Pilih rentang tanggal',
        context: context,
        firstDate: DateTime(2000),
        lastDate: DateTime(DateTime.now().year + 1, 12, 31),
        initialDateRange: _range,
      );
      if (!mounted) return;
      if (range == null) {
        setState(() => _periodRevision++);
        return;
      }
      _range = range;
    }
    setState(() => _period = value);
    await _load(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    final entries = searchLoadedLogbooks(_entries, _search);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Daftar Logbook'),
        actions: [
          IconButton(
            tooltip: 'Muat ulang',
            onPressed: () => _load(reset: true),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _load(reset: true),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Kelola dan pantau catatan aktivitas operasional Kebun Sei.',
            ),
            const SizedBox(height: 16),
            TextField(
              decoration: const InputDecoration(
                labelText: 'Cari judul atau catatan',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 350), () {
                  if (mounted) setState(() => _search = value);
                });
              },
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Pencarian hanya pada catatan yang sudah dimuat. Muat halaman berikutnya untuk memperluas pencarian.',
              ),
            ),
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth >= 700
                    ? (constraints.maxWidth - 24) / 3
                    : constraints.maxWidth;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: width,
                      child: DropdownButtonFormField<String>(
                        key: ValueKey('module-$_module'),
                        initialValue: _module ?? '',
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Modul'),
                        items: [
                          const DropdownMenuItem(
                            value: '',
                            child: Text('Semua Modul'),
                          ),
                          for (final spec in logbookModuleSpecs)
                            DropdownMenuItem(
                              value: spec.moduleType,
                              child: Text(FarmModules.nameOf(spec.moduleType)),
                            ),
                        ],
                        onChanged: (value) {
                          setState(() => _module = value == '' ? null : value);
                          _load(reset: true);
                        },
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: DropdownButtonFormField<String>(
                        key: ValueKey('period-$_period-$_periodRevision'),
                        initialValue: _period,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Tanggal'),
                        items: [
                          for (final p in [
                            'Semua tanggal',
                            'Hari ini',
                            '7 hari terakhir',
                            'Bulan ini',
                            'Rentang tanggal',
                          ])
                            DropdownMenuItem(value: p, child: Text(p)),
                        ],
                        onChanged: (value) {
                          if (value != null) _setPeriod(value);
                        },
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: DropdownButtonFormField<bool>(
                        initialValue: _newest,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Urutan'),
                        items: const [
                          DropdownMenuItem(value: true, child: Text('Terbaru')),
                          DropdownMenuItem(
                            value: false,
                            child: Text('Terlama'),
                          ),
                        ],
                        onChanged: (value) {
                          setState(() => _newest = value ?? true);
                          _load(reset: true);
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
            if (_period == 'Rentang tanggal' && _range != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  '${DateFormat('dd/MM/yyyy').format(_range!.start)} – ${DateFormat('dd/MM/yyyy').format(_range!.end)}',
                ),
              ),
            const SizedBox(height: 16),
            if (!_loading && _error == null && entries.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Tidak ada catatan yang cocok.'),
              ),
            for (final entry in entries)
              _LogbookCard(
                entry: entry,
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => LogbookDetailScreen(
                        service: widget.service,
                        entryId: entry.id,
                        userId: widget.userId,
                        canEdit: widget.canEdit,
                      ),
                    ),
                  );
                  if (mounted) _load(reset: true);
                },
              ),
            if (_error != null)
              Column(
                children: [
                  const Text(
                    'Catatan gagal dimuat. Periksa koneksi dan coba lagi.',
                  ),
                  TextButton(
                    onPressed: () => _load(reset: _page == null),
                    child: const Text('Coba lagi'),
                  ),
                ],
              ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_page?.hasMore == true)
              OutlinedButton(
                onPressed: () => _load(),
                child: const Text('Muat berikutnya'),
              )
            else if (_error == null)
              const Center(child: Text('Tidak ada data tambahan.')),
          ],
        ),
      ),
    );
  }
}

class _LogbookCard extends StatelessWidget {
  const _LogbookCard({required this.entry, required this.onTap});
  final LogbookEntry entry;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final spec = moduleSpecFor(entry.moduleId);
    final details = displayLogbookDetails(
      entry.moduleId,
      entry.details,
    ).entries.take(3);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(spec.icon, color: spec.color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      FarmModules.nameOf(entry.moduleId),
                      style: TextStyle(
                        color: spec.color,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(entry.title, style: Theme.of(context).textTheme.titleMedium),
              Text(
                DateFormat(
                  'dd MMM yyyy, HH:mm',
                  'id_ID',
                ).format(entry.activityDate.toLocal()),
              ),
              Text(
                'Status: ${logbookStatusLabel(entry.status)}',
                style: const TextStyle(color: AppColors.primaryGreen),
              ),
              for (final detail in details)
                Text('${detail.key}: ${detail.value}'),
              if (entry.note.isNotEmpty)
                Text(entry.note, maxLines: 2, overflow: TextOverflow.ellipsis),
              TextButton(onPressed: onTap, child: const Text('Lihat Detail')),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../../core/constants/farm_modules.dart';
import '../../logbook/services/logbook_service.dart';
import '../models/cultivation_batch.dart';
import '../services/batch_service.dart';
import '../widgets/batch_card.dart';
import 'batch_detail_screen.dart';
import 'batch_form_screen.dart';

class BatchListScreen extends StatefulWidget {
  const BatchListScreen({
    required this.service,
    required this.logbookService,
    required this.userId,
    required this.canManage,
    this.initialModule,
    this.selectActive = false,
    super.key,
  });
  final BatchService service;
  final LogbookService logbookService;
  final String userId;
  final bool canManage, selectActive;
  final String? initialModule;
  @override
  State<BatchListScreen> createState() => _BatchListScreenState();
}

class _BatchListScreenState extends State<BatchListScreen> {
  String? _module, _status;
  String _search = '';
  bool _newest = true, _loading = false, _more = true;
  String? _error;
  int _generation = 0;
  List<CultivationBatch> _entries = [];
  DocumentSnapshot<Map<String, dynamic>>? _cursor;
  @override
  void initState() {
    super.initState();
    _module = widget.initialModule;
    _status = widget.selectActive ? 'active' : null;
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    if (!reset && (_loading || !_more)) return;
    if (reset) {
      _generation++;
      _entries = [];
      _cursor = null;
      _more = true;
    }
    final generation = _generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.service.getPage(
        moduleType: _module,
        status: _status,
        newestFirst: _newest,
        cursor: _cursor,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _entries = {
          for (final b in [..._entries, ...page.entries]) b.id: b,
        }.values.toList();
        _cursor = page.cursor;
        _more = page.hasMore;
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _error = 'Daftar batch gagal dimuat.');
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _add() async {
    final id = await Navigator.push<String>(
      context,
      MaterialPageRoute<String>(
        builder: (_) => BatchFormScreen(
          service: widget.service,
          userId: widget.userId,
          initialModule: _module,
        ),
      ),
    );
    if (!mounted) return;
    if (id != null) {
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => BatchDetailScreen(
            batchId: id,
            service: widget.service,
            logbookService: widget.logbookService,
            userId: widget.userId,
            canManage: widget.canManage,
          ),
        ),
      );
    }
    if (mounted) _load(reset: true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.selectActive ? 'Pilih Batch Aktif' : 'Manajemen Batch Budidaya',
      ),
      actions: [
        IconButton(
          tooltip: 'Muat ulang',
          onPressed: () => _load(reset: true),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Manajemen Batch Budidaya',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const Text('Kelola kelompok dan siklus budidaya Kebun Sei.'),
            if (widget.canManage)
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: _add,
                  icon: const Icon(Icons.add),
                  label: const Text('Tambah Batch'),
                ),
              ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey('module-$_module'),
              initialValue: _module ?? '',
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Filter modul'),
              items: [
                const DropdownMenuItem(value: '', child: Text('Semua Modul')),
                ...FarmModules.values.map(
                  (m) => DropdownMenuItem(value: m.id, child: Text(m.name)),
                ),
              ],
              onChanged: widget.selectActive
                  ? null
                  : (v) {
                      _module = v == '' ? null : v;
                      _load(reset: true);
                    },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _status ?? '',
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Filter status'),
              items: [
                const DropdownMenuItem(value: '', child: Text('Semua Status')),
                ...batchStatuses.map(
                  (s) => DropdownMenuItem(
                    value: s,
                    child: Text(batchStatusLabel(s)),
                  ),
                ),
              ],
              onChanged: widget.selectActive
                  ? null
                  : (v) {
                      _status = v == '' ? null : v;
                      _load(reset: true);
                    },
            ),
            const SizedBox(height: 12),
            TextField(
              decoration: const InputDecoration(
                labelText: 'Cari nama / kode batch',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) =>
                  setState(() => _search = v.trim().toLowerCase()),
            ),
            const Text('Pencarian hanya pada data yang sudah dimuat.'),
            DropdownButton<bool>(
              value: _newest,
              isExpanded: true,
              items: const [
                DropdownMenuItem(value: true, child: Text('Terbaru')),
                DropdownMenuItem(value: false, child: Text('Terlama')),
              ],
              onChanged: (v) {
                _newest = v!;
                _load(reset: true);
              },
            ),
            if (_loading) const Center(child: CircularProgressIndicator()),
            if (_error != null)
              Column(
                children: [
                  Text(_error!),
                  TextButton(
                    onPressed: () => _load(reset: _entries.isEmpty),
                    child: const Text('Coba lagi'),
                  ),
                ],
              ),
            if (!_loading && _error == null && _entries.isEmpty)
              Text(
                widget.selectActive
                    ? 'Belum ada batch aktif untuk modul ini. Buat batch dan aktifkan melalui Detail Batch, atau gunakan Tanpa Batch untuk aktivitas umum.'
                    : 'Belum ada batch sesuai filter.',
              ),
            if (_entries.isNotEmpty &&
                !_loading &&
                !_entries.any(
                  (b) => '${b.input.name} ${b.input.code}'
                      .toLowerCase()
                      .contains(_search),
                ))
              const Text('Tidak ada hasil pada data yang dimuat.'),
            for (final b in _entries.where(
              (b) => '${b.input.name} ${b.input.code}'.toLowerCase().contains(
                _search,
              ),
            ))
              BatchCard(
                batch: b,
                selecting: widget.selectActive,
                onTap: () async {
                  if (widget.selectActive) {
                    Navigator.pop(context, b);
                    return;
                  }
                  await Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => BatchDetailScreen(
                        batchId: b.id,
                        service: widget.service,
                        logbookService: widget.logbookService,
                        userId: widget.userId,
                        canManage: widget.canManage,
                      ),
                    ),
                  );
                  if (mounted) _load(reset: true);
                },
              ),
            if (_entries.isNotEmpty && _more)
              OutlinedButton(
                onPressed: _loading ? null : () => _load(),
                child: const Text('Muat lebih banyak'),
              ),
            if (_entries.isNotEmpty && !_more)
              const Text('Semua halaman telah dimuat.'),
          ],
        ),
      ),
    ),
  );
}

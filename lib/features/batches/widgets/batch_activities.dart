import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../logbook/models/logbook_entry.dart';
import '../../logbook/models/logbook_form_spec.dart';
import '../../logbook/models/logbook_page.dart';
import '../../logbook/screen/logbook_detail_screen.dart';
import '../../logbook/services/logbook_service.dart';
import 'batch_card.dart';

class BatchActivities extends StatefulWidget {
  const BatchActivities({
    required this.batchId,
    required this.service,
    required this.userId,
    required this.canEdit,
    super.key,
  });
  final String batchId, userId;
  final LogbookService service;
  final bool canEdit;
  @override
  State<BatchActivities> createState() => _BatchActivitiesState();
}

class _BatchActivitiesState extends State<BatchActivities> {
  List<LogbookEntry> _entries = [];
  DocumentSnapshot<Map<String, dynamic>>? _cursor;
  bool _loading = false, _more = true, _loaded = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_loading || !_more) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.service.getPage(
        filter: LogbookFilter(batchId: widget.batchId),
        cursor: _cursor,
      );
      if (!mounted) return;
      setState(() {
        _loaded = true;
        _entries = mergeLogbookPages(_entries, page.entries);
        _cursor = page.cursor;
        _more = page.hasMore;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Aktivitas gagal dimuat.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('Ringkasan Batch', style: Theme.of(context).textTheme.titleLarge),
      Text(
        'Aktivitas pada halaman yang dimuat: ${_loaded ? _entries.length : 'Belum tersedia'}',
      ),
      Text(
        'Aktivitas terakhir: ${!_loaded
            ? 'Belum tersedia'
            : _entries.isEmpty
            ? 'Belum ada data'
            : batchDate(_entries.first.activityDate)}',
      ),
      const Text(
        'Populasi terkini, produksi kumulatif dan panen aktual: Belum dapat dihitung. Data awal dan estimasi panen bukan hasil produksi.',
      ),
      const SizedBox(height: 20),
      Text('Aktivitas Batch', style: Theme.of(context).textTheme.titleLarge),
      if (_loading) const Center(child: CircularProgressIndicator()),
      if (_error != null)
        Column(
          children: [
            Text(_error!),
            TextButton(
              onPressed: _load,
              child: const Text('Coba lagi aktivitas'),
            ),
          ],
        ),
      if (!_loading && _error == null && _entries.isEmpty)
        const Text('Belum ada data aktivitas.'),
      for (final e in _entries)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(batchDate(e.activityDate)),
                Text(e.title, style: Theme.of(context).textTheme.titleMedium),
                for (final d in displayLogbookDetails(
                  e.moduleId,
                  e.details,
                ).entries.take(3))
                  Text('${d.key}: ${d.value}'),
                if (e.note.isNotEmpty)
                  Text(e.note, maxLines: 3, overflow: TextOverflow.ellipsis),
                TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => LogbookDetailScreen(
                        service: widget.service,
                        entryId: e.id,
                        userId: widget.userId,
                        canEdit: widget.canEdit,
                      ),
                    ),
                  ),
                  child: const Text('Lihat Detail Logbook'),
                ),
              ],
            ),
          ),
        ),
      if (_more && _entries.isNotEmpty)
        OutlinedButton(
          onPressed: _loading ? null : _load,
          child: const Text('Muat aktivitas berikutnya'),
        ),
      if (!_more && _entries.isNotEmpty)
        const Text('Seluruh halaman aktivitas telah dimuat.'),
    ],
  );
}

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/farm_modules.dart';
import '../models/logbook_entry.dart';
import '../models/logbook_form_spec.dart';
import '../models/logbook_page.dart';
import '../services/logbook_service.dart';

class LogbookDetailScreen extends StatefulWidget {
  const LogbookDetailScreen({
    required this.service,
    required this.entryId,
    required this.userId,
    required this.canEdit,
    super.key,
  });
  final LogbookService service;
  final String entryId;
  final String userId;
  final bool canEdit;
  @override
  State<LogbookDetailScreen> createState() => _LogbookDetailScreenState();
}

class _LogbookDetailScreenState extends State<LogbookDetailScreen> {
  late Future<LogbookEntry?> _entry;
  Future<LogbookLinks>? _links;
  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _entry = widget.service.getEntry(widget.entryId);
    _links = null;
  }

  Future<void> _edit(LogbookEntry entry) async {
    final controller = TextEditingController(text: entry.note);
    bool saving = false;
    String? error;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => PopScope(
          canPop: !saving,
          child: AlertDialog(
            title: const Text('Edit Catatan Tambahan'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Perubahan stok, produksi, dan rincian pengamatan memerlukan proses koreksi tersendiri. Catatan asli pada rincian tetap dipertahankan.',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    enabled: !saving,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'Catatan tambahan',
                    ),
                  ),
                  if (error != null)
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(dialogContext),
                child: const Text('Batal'),
              ),
              FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        update(() {
                          saving = true;
                          error = null;
                        });
                        try {
                          await widget.service.updateNotes(
                            entry.id,
                            notes: controller.text,
                            userId: widget.userId,
                            expectedUpdatedAt: entry.updatedAt,
                          );
                          if (!dialogContext.mounted) return;
                          Navigator.pop(dialogContext);
                          if (mounted) setState(_reload);
                        } catch (_) {
                          if (dialogContext.mounted) {
                            update(() {
                              saving = false;
                              error =
                                  'Gagal menyimpan. Jika catatan berubah, tutup dan muat ulang terlebih dahulu.';
                            });
                          }
                        }
                      },
                child: Text(saving ? 'Menyimpan...' : 'Simpan'),
              ),
            ],
          ),
        ),
      ),
    );
    // The dialog route can still animate after its future completes.
    // TextEditingController is released after that animation.
    Future<void>.delayed(const Duration(milliseconds: 400), controller.dispose);
  }

  String _date(DateTime value) => value.millisecondsSinceEpoch == 0
      ? 'Belum tersedia'
      : DateFormat('dd MMM yyyy, HH:mm', 'id_ID').format(value.toLocal());
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Detail Logbook'),
      actions: [
        IconButton(
          tooltip: 'Muat ulang',
          onPressed: () => setState(_reload),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: FutureBuilder<LogbookEntry?>(
      future: _entry,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Detail gagal dimuat.'),
                TextButton(
                  onPressed: () => setState(_reload),
                  child: const Text('Coba lagi'),
                ),
              ],
            ),
          );
        }
        final entry = snapshot.data;
        if (entry == null || entry.isDeleted) {
          return const Center(
            child: Text('Catatan tidak tersedia atau sudah dibatalkan.'),
          );
        }
        final spec = moduleSpecFor(entry.moduleId);
        final details = displayLogbookDetails(entry.moduleId, entry.details);
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(spec.icon, color: spec.color, size: 32),
                    const SizedBox(height: 8),
                    Text(
                      entry.title,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    _line('Batch', entry.batchId ?? 'Belum terhubung ke batch'),
                    _line('Modul', FarmModules.nameOf(entry.moduleId)),
                    _line(
                      'Jenis aktivitas',
                      humanizeLogbookKey(entry.activityType),
                    ),
                    _line('Tanggal aktivitas', _date(entry.activityDate)),
                    _line('Status', logbookStatusLabel(entry.status)),
                    if (entry.hasQuantity && entry.unit.isNotEmpty)
                      _line(
                        'Kuantitas tercatat',
                        '${displayLogbookValue(entry.quantity)} ${entry.unit}',
                      ),
                    if (entry.createdBy.isNotEmpty)
                      _line('ID pembuat', entry.createdBy),
                    _line('Dibuat', _date(entry.createdAt)),
                    _line('Terakhir diperbarui', _date(entry.updatedAt)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Rincian Aktivitas',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (details.isEmpty)
              const Text('Rincian pengamatan belum tersedia.'),
            for (final e in details.entries) _line(e.key, e.value),
            const SizedBox(height: 16),
            Text(
              'Catatan Tambahan',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(
              entry.note.isEmpty ? 'Belum ada catatan tambahan.' : entry.note,
            ),
            if (widget.canEdit)
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () => _edit(entry),
                  icon: const Icon(Icons.edit_note),
                  label: const Text('Edit Catatan Tambahan'),
                ),
              ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Koreksi data stok/produksi dan pembatalan belum tersedia. Histori dipertahankan untuk pemeriksaan.',
              ),
            ),
            Text(
              'Keterkaitan Data',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            FutureBuilder<LogbookLinks>(
              future: _links ??= widget.service.getLinks(widget.entryId),
              builder: (context, links) {
                if (links.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (links.hasError) {
                  return Column(
                    children: [
                      const Text('Data terkait gagal dimuat.'),
                      TextButton(
                        onPressed: () => setState(() {
                          _links = widget.service.getLinks(widget.entryId);
                        }),
                        child: const Text('Coba lagi data terkait'),
                      ),
                    ],
                  );
                }
                final data = links.data!;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Transaksi inventaris'),
                    if (data.inventory.isEmpty)
                      const Text('Tidak ada transaksi inventaris terkait.'),
                    for (final row in data.inventory)
                      _line(
                        '${row['itemName'] ?? 'Item'} · ${switch (row['type']) {
                          'out' => 'Keluar',
                          'in' => 'Masuk',
                          _ => 'Jenis belum tersedia',
                        }}',
                        '${row['quantity'] == null ? 'Jumlah belum tersedia' : displayLogbookValue(row['quantity'])} ${row['unit'] ?? ''}${row['isReversed'] == true ? ' (dibalik)' : ''}',
                      ),
                    const SizedBox(height: 12),
                    const Text('Hasil produksi / panen'),
                    if (data.production.isEmpty)
                      const Text('Tidak ada hasil produksi terkait.'),
                    for (final row in data.production)
                      _line(
                        '${row['productName'] ?? 'Hasil produksi'}',
                        '${row['quantity'] == null ? 'Jumlah belum tersedia' : displayLogbookValue(row['quantity'])} ${row['unit'] ?? ''}',
                      ),
                    if (data.inventory.length == 50 ||
                        data.production.length == 50)
                      const Text(
                        'Menampilkan maksimal 50 data per jenis relasi.',
                      ),
                  ],
                );
              },
            ),
          ],
        );
      },
    ),
  );
  Widget _line(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Text('$label: $value'),
  );
}

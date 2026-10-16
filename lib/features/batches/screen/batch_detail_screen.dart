import 'package:flutter/material.dart';
import '../../inventory/screen/inventory_history_screen.dart';
import '../../schedule/screen/schedule_screen.dart';
import '../../../core/constants/farm_modules.dart';
import '../../logbook/services/logbook_service.dart';
import '../models/cultivation_batch.dart';
import '../services/batch_service.dart';
import '../widgets/batch_activities.dart';
import '../widgets/batch_card.dart';
import 'batch_form_screen.dart';

class BatchDetailScreen extends StatefulWidget {
  const BatchDetailScreen({
    required this.batchId,
    required this.service,
    required this.logbookService,
    required this.userId,
    required this.canManage,
    super.key,
  });
  final String batchId, userId;
  final BatchService service;
  final LogbookService logbookService;
  final bool canManage;
  @override
  State<BatchDetailScreen> createState() => _BatchDetailScreenState();
}

class _BatchDetailScreenState extends State<BatchDetailScreen> {
  late Future<CultivationBatch?> _future;
  bool _busy = false;
  int _revision = 0;
  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _revision++;
    _future = widget.service.getBatch(widget.batchId);
  }

  Future<void> _transition(CultivationBatch b) async {
    if (_busy) return;
    final to = nextBatchStatus(b.status)!;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Ubah status menjadi ${batchStatusLabel(to)}?'),
        content: const Text(
          'Perubahan status tidak mengubah stok atau membuat panen. Batch selesai tidak dapat menerima catatan baru. Transisi tidak dapat dibuka kembali melalui aplikasi.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Ubah Status'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.service.transition(
        b.id,
        from: b.status,
        to: to,
        userId: widget.userId,
      );
      if (mounted) setState(_reload);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Gagal mengubah status: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Detail Batch'),
      actions: [
        IconButton(
          tooltip: 'Muat ulang',
          onPressed: _busy ? null : () => setState(_reload),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: FutureBuilder<CultivationBatch?>(
      future: _future,
      builder: (context, s) {
        if (s.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (s.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Detail batch gagal dimuat.'),
                TextButton(
                  onPressed: () => setState(_reload),
                  child: const Text('Coba lagi'),
                ),
              ],
            ),
          );
        }
        final b = s.data;
        if (b == null) {
          return const Center(child: Text('Batch tidak tersedia.'));
        }
        final i = b.input;
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(i.name, style: Theme.of(context).textTheme.headlineSmall),
                Text('Modul: ${FarmModules.nameOf(i.moduleType)}'),
                Text('Kode: ${i.code}'),
                Text('Lokasi: ${i.locationName}'),
                Text('Status: ${batchStatusLabel(b.status)}'),
                Text('Mulai: ${batchDate(i.startedAt)}'),
                Text('Estimasi panen: ${batchDate(i.expectedHarvestAt)}'),
                Text('Tanggal selesai siklus: ${batchDate(b.completedAt)}'),
                Text(
                  'Jumlah awal: ${i.initialQuantity == null ? 'Belum ada data' : '${i.initialQuantity} ${i.initialUnit}'}',
                ),
                const Text(
                  'Jumlah awal bukan populasi hidup terkini. Tanggal selesai siklus bukan tanggal panen aktual.',
                ),
                if (i.commodity.isNotEmpty)
                  Text('Komoditas / jenis: ${i.commodity}'),
                Text(
                  'Catatan: ${i.notes.isEmpty ? 'Belum ada data' : i.notes}',
                ),
                Text('Pembuat: ${b.createdBy}'),
                Text('Dibuat: ${batchDate(b.createdAt)}'),
                Text('Pengubah: ${b.updatedBy}'),
                Text('Diperbarui: ${batchDate(b.updatedAt)}'),
                if (widget.canManage)
                  Wrap(
                    spacing: 12,
                    children: [
                      if (['planned', 'active'].contains(b.status))
                        OutlinedButton(
                          onPressed: _busy
                              ? null
                              : () async {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute<String>(
                                      builder: (_) => BatchFormScreen(
                                        service: widget.service,
                                        userId: widget.userId,
                                        batch: b,
                                      ),
                                    ),
                                  );
                                  if (mounted) setState(_reload);
                                },
                          child: const Text('Edit Batch'),
                        ),
                      if (nextBatchStatus(b.status) != null)
                        FilledButton(
                          onPressed: _busy ? null : () => _transition(b),
                          child: Text(
                            _busy
                                ? 'Menyimpan...'
                                : 'Ubah ke ${batchStatusLabel(nextBatchStatus(b.status)!)}',
                          ),
                        ),
                    ],
                  ),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => InventoryHistoryScreen(
                        userId: widget.userId,
                        canEdit: widget.canManage,
                        field: 'batchId',
                        value: b.id,
                        service: widget.logbookService.inventoryHistory,
                        logbookService: widget.logbookService,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.inventory_2_outlined),
                  label: const Text('Mutasi Stok Batch'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    try {
                      final profile = await widget.logbookService
                          .operationalProfile(widget.userId);
                      if (!context.mounted) return;
                      if (profile == null || !profile.canViewSchedules) {
                        throw StateError('Tidak memiliki akses jadwal.');
                      }
                      Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => Scaffold(
                            appBar: AppBar(title: const Text('Jadwal Batch')),
                            body: ScheduleScreen(
                              profile: profile,
                              batchId: b.id,
                              service: widget.logbookService.schedules,
                              logbooks: widget.logbookService,
                            ),
                          ),
                        ),
                      );
                    } catch (error) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Jadwal batch belum dapat dibuka: $error',
                            ),
                          ),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.event_note_outlined),
                  label: const Text('Jadwal Batch'),
                ),
                BatchActivities(
                  key: ValueKey(_revision),
                  batchId: b.id,
                  service: widget.logbookService,
                  userId: widget.userId,
                  canEdit: widget.canManage,
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

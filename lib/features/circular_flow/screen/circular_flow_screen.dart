import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../../core/constants/farm_modules.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/operation_error.dart';
import '../../../core/widgets/app_ui.dart';
import '../../../core/widgets/feature_page.dart';
import '../../../core/widgets/firestore_paged_list.dart';
import '../../../core/widgets/period_filter.dart';
import '../../batches/widgets/operational_batch_picker.dart';
import '../../profile/models/app_user.dart';
import '../models/circular_flow.dart';
import '../services/circular_flow_service.dart';

class CircularFlowScreen extends StatefulWidget {
  const CircularFlowScreen({required this.profile, this.service, super.key});
  final AppUser profile;
  final CircularFlowService? service;
  @override
  State<CircularFlowScreen> createState() => _CircularFlowScreenState();
}

class _CircularFlowScreenState extends State<CircularFlowScreen> {
  late final _service = widget.service ?? CircularFlowService();
  DateTimeRange _period = monthPeriod();
  String? _source, _destination, _material;
  int _revision = 0;
  Future<void> _create() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          CircularFlowForm(service: _service, userId: widget.profile.uid),
    );
    if (result == true && mounted) {
      setState(() => _revision++);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Aliran aktual tercatat. Saldo stok tidak diubah.'),
        ),
      );
    }
  }

  Future<void> _detail(CircularFlow f) => showDialog<void>(
    context: context,
    builder: (_) => AppDialogShell(
      title: 'Detail Aliran Material',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(f.materialName),
          Text('${f.quantity} ${f.unit}'),
          Text(
            '${FarmModules.nameOf(f.sourceModuleType)} → ${FarmModules.nameOf(f.destinationModuleType)}',
          ),
          Text(shortDateFormat.format(f.flowDate)),
          Text(
            'Petugas: ${f.createdByName.isNotEmpty ? f.createdByName : (f.createdBy.isEmpty ? "Belum tercatat" : f.createdBy)}',
          ),
          Text(
            f.isActual
                ? 'Aliran aktual · Pencatatan manual'
                : 'Data lama; asal aktivitas belum terverifikasi',
          ),
          if (f.sourceBatchId != null)
            SelectableText('Batch sumber: ${f.sourceBatchId}'),
          if (f.destinationBatchId != null)
            SelectableText('Batch tujuan: ${f.destinationBatchId}'),
          if (f.logbookId != null) SelectableText('Logbook: ${f.logbookId}'),
          if (f.inventoryTransactionId != null)
            SelectableText('Mutasi terkait: ${f.inventoryTransactionId}'),
          Text(f.notes),
          const Text(
            'Catatan ini tidak membuat mutasi stok atau transfer lokasi.',
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Tutup'),
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) {
    if (!widget.profile.canViewCircularFlows) {
      return const Center(child: Text('Akses ditolak.'));
    }
    return FeaturePage(
      title: 'Aliran Nutrisi Aktual',
      subtitle:
          'Catat perpindahan material yang benar-benar terjadi. Ilustrasi Dashboard merupakan konsep.',
      actions: [
        IconButton(
          onPressed: () => setState(() => _revision++),
          tooltip: 'Muat ulang',
          icon: const Icon(Icons.refresh),
        ),
        if (widget.profile.canManageCircularFlows)
          FilledButton.icon(
            onPressed: _create,
            icon: const Icon(Icons.add),
            label: const Text('Catat Aliran'),
          ),
      ],
      child: Column(
        children: [
          Expanded(
            child: FirestorePagedList<CircularFlow>(
              header: ExpansionTile(
                title: const Text('Periode dan filter aliran'),
                children: [
                  PeriodFilter(
                    value: _period,
                    onChanged: (v) => setState(() {
                      _period = v;
                      _revision++;
                    }),
                  ),
                  for (final source in [true, false])
                    DropdownButtonFormField<String>(
                      initialValue: '',
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: source ? 'Modul sumber' : 'Modul tujuan',
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: '',
                          child: Text('Semua modul'),
                        ),
                        for (final m in FarmModules.values)
                          DropdownMenuItem(value: m.id, child: Text(m.name)),
                      ],
                      onChanged: (v) => setState(() {
                        if (source) {
                          _source = v == '' ? null : v;
                        } else {
                          _destination = v == '' ? null : v;
                        }
                        _revision++;
                      }),
                    ),
                  TextField(
                    decoration: const InputDecoration(
                      labelText: 'Nama material',
                      helperText:
                          'Tekan Enter untuk menerapkan nama material lengkap.',
                    ),
                    onSubmitted: (v) => setState(() {
                      _material = v.trim().isEmpty ? null : v.trim();
                      _revision++;
                    }),
                  ),
                ],
              ),
              queryKey: _revision,
              load: (cursor) => _service.fetchPage(
                start: _period.start,
                end: _period.end,
                source: _source,
                destination: _destination,
                material: _material,
                cursor: cursor,
              ),
              itemBuilder: (f) => AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      f.materialName,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      '${f.quantity} ${f.unit} · ${shortDateFormat.format(f.flowDate)}',
                    ),
                    Text(
                      '${FarmModules.nameOf(f.sourceModuleType)} → ${FarmModules.nameOf(f.destinationModuleType)}',
                    ),
                    if (!f.isActual)
                      const Text(
                        'Data lama / ilustrasi: belum terverifikasi sebagai aliran aktual.',
                      ),
                    TextButton(
                      onPressed: () => _detail(f),
                      child: const Text('Detail Aliran'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CircularFlowForm extends StatefulWidget {
  const CircularFlowForm({
    required this.service,
    required this.userId,
    super.key,
  });
  final CircularFlowService service;
  final String userId;
  @override
  State<CircularFlowForm> createState() => _CircularFlowFormState();
}

class _CircularFlowFormState extends State<CircularFlowForm> {
  final _key = GlobalKey<FormState>();
  final _requestId = const Uuid().v4();
  final _material = TextEditingController(),
      _quantity = TextEditingController(),
      _notes = TextEditingController();
  String? _source, _destination, _sourceBatch, _destinationBatch;
  String _unit = 'kg';
  FlowReference? _logbook, _ledger;
  DateTime _date = DateTime.now();
  bool _saving = false;
  String? _error;
  @override
  void dispose() {
    _material.dispose();
    _quantity.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickReference(bool logbook) async {
    final kind = logbook ? 'logbooks' : 'inventory_transactions';
    final r = await showDialog<FlowReference>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(logbook ? 'Pilih Logbook Terkait' : 'Pilih Mutasi Terkait'),
        content: SizedBox(
          width: 500,
          height: 400,
          child: FirestorePagedList<FlowReference>(
            queryKey: kind,
            load: (cursor) => widget.service.references(kind, cursor: cursor),
            itemBuilder: (r) => ListTile(
              title: Text(r.label),
              onTap: () => Navigator.pop(context, r),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
        ],
      ),
    );
    if (r != null && mounted) {
      setState(() {
        if (logbook) {
          _logbook = r;
        } else {
          _ledger = r;
        }
      });
    }
  }

  Future<void> _save() async {
    if (_saving || !_key.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.service.create(
        requestId: _requestId,
        userId: widget.userId,
        input: CircularFlowInput(
          logbookId: _logbook?.id,
          inventoryTransactionId: _ledger?.id,
          sourceModuleType: _source ?? '',
          destinationModuleType: _destination ?? '',
          sourceBatchId: _sourceBatch,
          destinationBatchId: _destinationBatch,
          materialName: _material.text,
          quantity: double.tryParse(_quantity.text.replaceAll(',', '.')) ?? 0,
          unit: _unit,
          flowDate: _date,
          notes: _notes.text,
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = operationError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AppDialogShell(
      title: 'Catat Aliran Aktual',
      content: AbsorbPointer(
        absorbing: _saving,
        child: Form(
          key: _key,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null)
                Text(_error!, style: const TextStyle(color: Colors.red)),
              const Text(
                'Pencatatan material aktual saja; tidak mengurangi stok. Jangan mengulangi pencatatan aktivitas yang sama.',
              ),
              for (final source in [true, false]) ...[
                DropdownButtonFormField<String>(
                  initialValue: source ? _source : _destination,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: source ? 'Modul sumber' : 'Modul tujuan',
                  ),
                  items: [
                    for (final m in FarmModules.values)
                      DropdownMenuItem(value: m.id, child: Text(m.name)),
                  ],
                  validator: (v) => v == null ? 'Pilih modul' : null,
                  onChanged: (v) => setState(() {
                    if (source) {
                      _source = v;
                      _sourceBatch = null;
                    } else {
                      _destination = v;
                      _destinationBatch = null;
                    }
                  }),
                ),
                if ((source ? _source : _destination) != null)
                  OperationalBatchPicker(
                    moduleId: (source ? _source : _destination)!,
                    batchId: source ? _sourceBatch : _destinationBatch,
                    userId: widget.userId,
                    onChanged: (v) => setState(() {
                      if (source) {
                        _sourceBatch = v;
                      } else {
                        _destinationBatch = v;
                      }
                    }),
                  ),
                const SizedBox(height: 12),
              ],
              TextFormField(
                controller: _material,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Material'),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Isi material' : null,
              ),
              TextFormField(
                controller: _quantity,
                textInputAction: TextInputAction.next,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Jumlah aktual'),
                validator: (v) {
                  final n = double.tryParse((v ?? '').replaceAll(',', '.'));
                  return n != null && n.isFinite && n > 0
                      ? null
                      : 'Isi angka positif';
                },
              ),
              DropdownButtonFormField<String>(
                initialValue: _unit,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Satuan'),
                items: [
                  for (final u in flowUnits)
                    DropdownMenuItem(value: u, child: Text(u)),
                ],
                onChanged: (v) => setState(() => _unit = v!),
              ),
              TextButton.icon(
                onPressed: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: _date,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (d != null && mounted) setState(() => _date = d);
                },
                icon: const Icon(Icons.calendar_today),
                label: Text(shortDateFormat.format(_date)),
              ),
              ExpansionTile(
                title: const Text('Referensi kegiatan (opsional)'),
                children: [
                  for (final isLogbook in [true, false]) ...[
                    OutlinedButton(
                      onPressed: () => _pickReference(isLogbook),
                      child: Text(
                        (isLogbook ? _logbook : _ledger)?.label ??
                            (isLogbook ? 'Pilih Logbook' : 'Pilih mutasi stok'),
                      ),
                    ),
                    if ((isLogbook ? _logbook : _ledger) != null)
                      TextButton(
                        onPressed: () => setState(() {
                          if (isLogbook) {
                            _logbook = null;
                          } else {
                            _ledger = null;
                          }
                        }),
                        child: const Text('Lepas referensi'),
                      ),
                  ],
                  const Text(
                    'Mutasi yang dirujuk harus sama jumlah, satuan dan modul. Stok tidak dikurangi lagi.',
                  ),
                ],
              ),
              TextFormField(
                controller: _notes,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Catatan',
                  helperText: 'Bukti kegiatan (opsional)',
                  helperMaxLines: 2,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Menyimpan...' : 'Simpan Aliran'),
        ),
      ],
    ),
  );
}

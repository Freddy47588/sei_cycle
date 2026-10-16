import 'package:flutter/material.dart';
import '../../../core/constants/farm_modules.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_ui.dart';
import '../../../core/widgets/feature_page.dart';
import '../../../core/widgets/firestore_paged_list.dart';
import '../../logbook/screen/logbook_detail_screen.dart';
import '../../logbook/services/logbook_service.dart';
import '../models/inventory_transaction.dart';
import '../services/inventory_transaction_service.dart';

class InventoryHistoryScreen extends StatefulWidget {
  const InventoryHistoryScreen({
    required this.userId,
    required this.canEdit,
    this.field,
    this.value,
    this.service,
    this.logbookService,
    super.key,
  });
  final String userId;
  final bool canEdit;
  final String? field, value;
  final InventoryTransactionService? service;
  final LogbookService? logbookService;
  @override
  State<InventoryHistoryScreen> createState() => _InventoryHistoryScreenState();
}

class _InventoryHistoryScreenState extends State<InventoryHistoryScreen> {
  late final _service = widget.service ?? InventoryTransactionService();
  late String _field = widget.field ?? 'all';
  late final _value = TextEditingController(text: widget.value);
  late String _applied = widget.value ?? '';
  DateTimeRange? _dates;
  int _revision = 0;
  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  Future<void> _pickDates() async {
    final dates = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: _dates,
    );
    if (dates != null && mounted) setState(() => _dates = dates);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Riwayat Mutasi Stok')),
    body: FeaturePage(
      title: 'Histori Persediaan',
      subtitle: 'Saldo adalah stok lokasi. Batch merupakan atribusi kegiatan.',
      actions: [
        IconButton(
          onPressed: () => setState(() => _revision++),
          tooltip: 'Muat ulang',
          icon: const Icon(Icons.refresh),
        ),
      ],
      child: Column(
        children: [
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(
              _field == 'all'
                  ? 'Filter histori'
                  : 'Filter: $_field = $_applied',
            ),
            children: [
              DropdownButtonFormField<String>(
                initialValue: _field,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Cari berdasarkan',
                ),
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('Semua mutasi')),
                  DropdownMenuItem(value: 'itemId', child: Text('ID Barang')),
                  DropdownMenuItem(value: 'batchId', child: Text('ID Batch')),
                  DropdownMenuItem(
                    value: 'logbookId',
                    child: Text('ID Logbook'),
                  ),
                  DropdownMenuItem(value: 'moduleType', child: Text('Modul')),
                  DropdownMenuItem(value: 'type', child: Text('Jenis mutasi')),
                  DropdownMenuItem(value: 'source', child: Text('Sumber')),
                ],
                onChanged: (v) => setState(() {
                  _field = v!;
                  _applied = '';
                  _value.clear();
                }),
              ),
              if (_field == 'moduleType')
                DropdownButtonFormField<String>(
                  key: ValueKey(_field),
                  decoration: const InputDecoration(labelText: 'Modul'),
                  items: [
                    for (final m in FarmModules.values)
                      DropdownMenuItem(value: m.id, child: Text(m.name)),
                  ],
                  onChanged: (v) => setState(() => _applied = v!),
                )
              else if (_field == 'type' || _field == 'source')
                DropdownButtonFormField<String>(
                  key: ValueKey(_field),
                  decoration: const InputDecoration(labelText: 'Nilai filter'),
                  items: [
                    for (final v
                        in _field == 'type'
                            ? ['in', 'out', 'correction', 'opening']
                            : ['manual', 'logbook', 'opening'])
                      DropdownMenuItem(value: v, child: Text(mutationLabel(v))),
                  ],
                  onChanged: (v) => setState(() => _applied = v!),
                )
              else if (_field != 'all')
                TextField(
                  controller: _value,
                  decoration: InputDecoration(
                    labelText: 'ID lengkap',
                    suffixIcon: IconButton(
                      onPressed: () =>
                          setState(() => _applied = _value.text.trim()),
                      icon: const Icon(Icons.search),
                      tooltip: 'Terapkan filter',
                    ),
                  ),
                  onSubmitted: (v) => setState(() => _applied = v.trim()),
                ),
              Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: _pickDates,
                    icon: const Icon(Icons.date_range),
                    label: Text(
                      _dates == null
                          ? 'Rentang tanggal'
                          : '${shortDateFormat.format(_dates!.start)} - ${shortDateFormat.format(_dates!.end)}',
                    ),
                  ),
                  if (_dates != null)
                    TextButton(
                      onPressed: () => setState(() => _dates = null),
                      child: const Text('Semua tanggal'),
                    ),
                ],
              ),
            ],
          ),
          Expanded(
            child: FirestorePagedList<InventoryTransaction>(
              idOf: (item) => item.id,
              queryKey: (_field, _applied, _dates, _revision),
              load: (cursor) => _service.fetchPage(
                field: _field == 'all' ? null : _field,
                value: _applied,
                cursor: cursor,
                from: _dates?.start,
                until: _dates == null
                    ? null
                    : DateTime(
                        _dates!.end.year,
                        _dates!.end.month,
                        _dates!.end.day + 1,
                      ),
              ),
              itemBuilder: (t) => AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.itemName,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text('${mutationLabel(t.type)} - ${t.quantity} ${t.unit}'),
                    Wrap(
                      spacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text('${t.beforeStock}'),
                        const Icon(Icons.arrow_forward, size: 16),
                        Text('${t.afterStock} ${t.unit}'),
                      ],
                    ),
                    Text(dateTimeFormat.format(t.transactionDate)),
                    Text(
                      'Sumber: ${mutationLabel(t.source)} - ${FarmModules.nameOf(t.moduleType)}',
                    ),
                    if (t.batchId != null) Text('Batch: ${t.batchId}'),
                    Text('Pengguna: ${t.createdBy}'),
                    if (t.notes.isNotEmpty) Text(t.notes),
                    if (t.isReversed)
                      const Text(
                        'DIBALIK - histori ini bukan mutasi aktif baru',
                      ),
                    if (t.logbookId.isNotEmpty)
                      TextButton(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => LogbookDetailScreen(
                              service:
                                  widget.logbookService ?? LogbookService(),
                              entryId: t.logbookId,
                              userId: widget.userId,
                              canEdit: widget.canEdit,
                            ),
                          ),
                        ),
                        child: Text('Buka Logbook ${t.logbookId}'),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

String mutationLabel(String type) => switch (type) {
  'in' => 'Stok Masuk',
  'out' => 'Stok Keluar',
  'correction' => 'Koreksi Stok',
  'opening' => 'Saldo Awal',
  'manual' => 'Manual',
  'logbook' => 'Logbook',
  _ => type,
};

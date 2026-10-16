import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../../core/constants/farm_modules.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/operation_error.dart';
import '../../../core/widgets/app_ui.dart';
import '../../../core/widgets/feature_page.dart';
import '../../../core/widgets/firestore_paged_list.dart';
import '../../../core/widgets/period_filter.dart';
import '../../inventory/models/inventory_item.dart';
import '../../inventory/screen/inventory_history_screen.dart';
import '../../profile/models/app_user.dart';
import '../../finance/screen/finance_detail_screen.dart';
import '../models/sale.dart';
import '../services/sales_service.dart';

class SalesScreen extends StatefulWidget {
  const SalesScreen({required this.profile, this.service, super.key});
  final AppUser profile;
  final SalesService? service;
  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  late final _service = widget.service ?? SalesService();
  DateTimeRange _period = monthPeriod();
  String? _module;
  String _search = '';
  int _revision = 0;
  Future<void> _create() async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SaleForm(service: _service, userId: widget.profile.uid),
    );
    if (saved == true && mounted) {
      setState(() => _revision++);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Penjualan, stok dan pemasukan tersimpan.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.profile.canViewSales) {
      return const Center(child: Text('Tidak memiliki akses penjualan.'));
    }
    return FeaturePage(
      title: 'Penjualan Hasil Panen',
      subtitle:
          'Penjualan langsung yang telah dibayar. Stok dan pemasukan dicatat bersama.',
      actions: [
        IconButton(
          onPressed: () => setState(() => _revision++),
          tooltip: 'Muat ulang',
          icon: const Icon(Icons.refresh),
        ),
        if (widget.profile.canManageSales)
          FilledButton.icon(
            onPressed: _create,
            icon: const Icon(Icons.add),
            label: const Text('Catat Penjualan'),
          ),
      ],
      child: Column(
        children: [
          Expanded(
            child: FirestorePagedList<Sale>(
              header: ExpansionTile(
                title: const Text('Periode dan filter penjualan'),
                children: [
                  PeriodFilter(
                    value: _period,
                    onChanged: (v) => setState(() {
                      _period = v;
                      _revision++;
                    }),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: '',
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Modul'),
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('Semua modul'),
                      ),
                      for (final m in FarmModules.values)
                        DropdownMenuItem(value: m.id, child: Text(m.name)),
                    ],
                    onChanged: (v) => setState(() {
                      _module = v == '' ? null : v;
                      _revision++;
                    }),
                  ),
                  TextField(
                    decoration: const InputDecoration(
                      labelText: 'Cari produk, nomor atau pembeli',
                      helperText: 'Pencarian pada penjualan yang sudah dimuat.',
                    ),
                    onChanged: (v) => setState(() => _search = v.toLowerCase()),
                  ),
                ],
              ),
              queryKey: _revision,
              load: (cursor) => _service.fetchPage(
                start: _period.start,
                end: _period.end,
                moduleType: _module,
                cursor: cursor,
              ),
              transform: (rows) => rows
                  .where(
                    (r) => '${r.productName} ${r.saleNumber} ${r.buyerName}'
                        .toLowerCase()
                        .contains(_search),
                  )
                  .toList(),
              itemBuilder: (r) => AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.productName,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      '${r.quantity} ${r.unit} × ${currencyFormat.format(r.unitPrice)}',
                    ),
                    Text(
                      currencyFormat.format(r.totalAmount),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      '${shortDateFormat.format(r.saleDate)} · ${r.paymentMethod} · Lunas',
                    ),
                    TextButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => SaleDetailScreen(
                            sale: r,
                            profile: widget.profile,
                          ),
                        ),
                      ),
                      child: const Text('Detail Penjualan'),
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

class SaleForm extends StatefulWidget {
  const SaleForm({
    required this.service,
    required this.userId,
    this.initialProduct,
    super.key,
  });
  final SalesService service;
  final String userId;
  final InventoryItem? initialProduct;
  @override
  State<SaleForm> createState() => _SaleFormState();
}

class _SaleFormState extends State<SaleForm> {
  final _key = GlobalKey<FormState>();
  final _requestId = const Uuid().v4();
  final _quantity = TextEditingController(),
      _price = TextEditingController(),
      _buyer = TextEditingController(),
      _notes = TextEditingController();
  late InventoryItem? _product = widget.initialProduct;
  DateTime _date = DateTime.now();
  String _payment = 'tunai';
  bool _saving = false;
  String? _error;
  SaleInput get _input => SaleInput(
    inventoryItemId: _product?.id ?? '',
    quantity: double.tryParse(_quantity.text.replaceAll(',', '.')) ?? 0,
    unit: _product?.unit ?? '',
    unitPrice: int.tryParse(_price.text) ?? 0,
    saleDate: _date,
    paymentMethod: _payment,
    buyerName: _buyer.text,
    notes: _notes.text,
  );
  @override
  void dispose() {
    for (final c in [_quantity, _price, _buyer, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pick() async {
    final product = await showDialog<InventoryItem>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Pilih hasil panen'),
        content: SizedBox(
          width: 500,
          height: 400,
          child: FirestorePagedList<InventoryItem>(
            queryKey: 'products',
            load: (cursor) => widget.service.products(cursor: cursor),
            itemBuilder: (p) => ListTile(
              title: Text(p.name),
              subtitle: Text('${p.currentStock} ${p.unit} tersedia'),
              onTap: () => Navigator.pop(context, p),
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
    if (product != null && mounted) setState(() => _product = product);
  }

  Future<void> _save() async {
    if (_saving || !_key.currentState!.validate()) return;
    final input = _input;
    try {
      input.validate();
    } catch (e) {
      setState(() => _error = operationError(e));
      return;
    }
    // Keep the form immutable while the final confirmation is shown.
    setState(() {
      _saving = true;
      _error = null;
    });
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Simpan penjualan lunas?'),
        content: Text(
          '${_product!.name}\n${input.quantity} ${input.unit} × ${currencyFormat.format(input.unitPrice)}\n'
          'Total ${currencyFormat.format(input.totalAmount)}\n'
          'Perkiraan sisa stok: ${_product!.currentStock - input.quantity} ${input.unit}. '
          'Stok diperiksa kembali saat penyimpanan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Periksa kembali'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Konfirmasi'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      if (mounted) setState(() => _saving = false);
      return;
    }
    try {
      await widget.service.create(
        requestId: _requestId,
        userId: widget.userId,
        input: input,
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
      title: 'Catat Penjualan',
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
              OutlinedButton.icon(
                onPressed: _pick,
                icon: const Icon(Icons.inventory_2_outlined),
                label: Text(
                  _product?.name ?? 'Pilih hasil panen yang layak dijual',
                ),
              ),
              if (_product != null)
                Text(
                  'Stok tersedia: ${_product!.currentStock} ${_product!.unit}',
                ),
              const Text(
                'Jika produk belum tersedia, tandai hasil panen layak dijual di Inventaris.',
              ),
              TextFormField(
                controller: _quantity,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'Kuantitas (${_product?.unit ?? "satuan produk"})',
                  helperText: 'Maksimal 3 angka desimal',
                ),
                validator: (v) =>
                    (double.tryParse((v ?? '').replaceAll(',', '.')) ?? 0) > 0
                    ? null
                    : 'Isi jumlah positif',
                onChanged: (_) => setState(() {}),
              ),
              TextFormField(
                controller: _price,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Harga satuan',
                  prefixText: 'Rp ',
                  helperText: 'Rupiah utuh per satuan produk',
                  helperMaxLines: 2,
                ),
                validator: (v) => (int.tryParse(v ?? '') ?? 0) > 0
                    ? null
                    : 'Isi harga Rupiah positif',
                onChanged: (_) => setState(() {}),
              ),
              Builder(
                builder: (_) {
                  try {
                    _input.validate();
                    return Text(
                      'Total: ${currencyFormat.format(_input.totalAmount)}',
                    );
                  } catch (_) {
                    return const Text(
                      'Total dihitung setelah produk, jumlah dan harga valid.',
                    );
                  }
                },
              ),
              TextButton.icon(
                onPressed: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: _date,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (date != null && mounted) setState(() => _date = date);
                },
                icon: const Icon(Icons.calendar_today),
                label: Text(shortDateFormat.format(_date)),
              ),
              DropdownButtonFormField<String>(
                initialValue: _payment,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Metode pembayaran',
                ),
                items: [
                  for (final p in salePaymentMethods)
                    DropdownMenuItem(value: p, child: Text(p)),
                ],
                onChanged: (v) => setState(() => _payment = v!),
              ),
              TextFormField(
                controller: _buyer,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Pembeli (opsional)',
                ),
              ),
              TextFormField(
                controller: _notes,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Catatan (opsional)',
                ),
              ),
              const Text(
                'Stok gabungan tidak diberi batch asal secara otomatis. Penjualan selesai menjadi histori permanen.',
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
          child: Text(_saving ? 'Menyimpan...' : 'Simpan Penjualan'),
        ),
      ],
    ),
  );
}

class SaleDetailScreen extends StatelessWidget {
  const SaleDetailScreen({
    required this.sale,
    required this.profile,
    super.key,
  });
  final Sale sale;
  final AppUser profile;
  @override
  Widget build(BuildContext context) {
    if (!profile.canViewSales) {
      return const Scaffold(body: Center(child: Text('Akses ditolak.')));
    }
    final s = sale;
    return Scaffold(
      appBar: AppBar(title: const Text('Detail Penjualan')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(s.saleNumber),
                Text(
                  s.productName,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text('Modul: ${FarmModules.nameOf(s.moduleType)}'),
                Text(
                  '${s.quantity} ${s.unit} × ${currencyFormat.format(s.unitPrice)}',
                ),
                Text('Total ${currencyFormat.format(s.totalAmount)}'),
                Text('Tanggal: ${shortDateFormat.format(s.saleDate)}'),
                Text(
                  'Pembayaran: ${s.paymentMethod} · ${s.status == "paid" ? "Lunas" : s.status}',
                ),
                Text(
                  'Pembeli: ${s.buyerName.isEmpty ? "Tidak dicatat" : s.buyerName}',
                ),
                Text(
                  'Pembuat: ${s.createdByName.isEmpty ? s.createdBy : s.createdByName}',
                ),
                Text('Dicatat: ${shortDateFormat.format(s.createdAt)}'),
                Text(s.notes),
                const Text(
                  'Batch asal tidak diatribusikan karena saldo merupakan stok gabungan.',
                ),
                TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => InventoryHistoryScreen(
                        userId: profile.uid,
                        canEdit: false,
                        field: 'itemId',
                        value: s.inventoryItemId,
                      ),
                    ),
                  ),
                  child: const Text('Barang dan Riwayat Stok'),
                ),
                TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => FinanceDetailScreen(
                        id: s.financeTransactionId,
                        profile: profile,
                      ),
                    ),
                  ),
                  child: const Text('Pemasukan Terkait'),
                ),
                SelectableText('Mutasi: ${s.inventoryTransactionId}'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

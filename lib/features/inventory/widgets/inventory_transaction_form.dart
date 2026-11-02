import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../../core/widgets/app_ui.dart';
import '../../batches/widgets/operational_batch_picker.dart';
import '../models/inventory_item.dart';
import '../services/inventory_adjustment_service.dart';
import 'inventory_master_form.dart';

class InventoryTransactionForm extends StatefulWidget {
  const InventoryTransactionForm({
    required this.item,
    required this.userId,
    required this.service,
    super.key,
  });
  final InventoryItem item;
  final String userId;
  final InventoryAdjustmentService service;
  @override
  State<InventoryTransactionForm> createState() =>
      _InventoryTransactionFormState();
}

class _InventoryTransactionFormState extends State<InventoryTransactionForm> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController(), _notes = TextEditingController();
  final _requestId = const Uuid().v4();
  String _type = 'in';
  String? _batchId, _error;
  bool _saving = false, _allowNegative = false;
  @override
  void dispose() {
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.service.mutate(
        requestId: _requestId,
        itemId: widget.item.id,
        type: _type,
        value: parseStock(_amount.text)!,
        unit: widget.item.unit,
        notes: _notes.text,
        userId: widget.userId,
        batchId: _batchId,
        allowNegative: _allowNegative,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AppDialogShell(
      title: 'Mutasi Stok — ${widget.item.name}',
      maxWidth: 500,
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Stok dimuat: ${widget.item.currentStock} ${widget.item.unit}. Saldo akhir dihitung dari stok terkini saat disimpan.',
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Jenis mutasi'),
              items: const [
                DropdownMenuItem(value: 'in', child: Text('Stok Masuk')),
                DropdownMenuItem(value: 'out', child: Text('Stok Keluar')),
                DropdownMenuItem(
                  value: 'correction',
                  child: Text('Koreksi Stok'),
                ),
              ],
              onChanged: _saving ? null : (v) => setState(() => _type = v!),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _amount,
              enabled: !_saving,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: _type == 'correction'
                    ? 'Stok fisik aktual (nilai absolut)'
                    : 'Jumlah (${widget.item.unit})',
              ),
              validator: (v) =>
                  stockValidator(v) ??
                  (_type != 'correction' && parseStock(v!) == 0
                      ? 'Jumlah harus lebih dari 0'
                      : null),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notes,
              enabled: !_saving,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Alasan / catatan'),
              validator: requiredInventoryText,
            ),
            const SizedBox(height: 12),
            OperationalBatchPicker(
              moduleId: widget.item.moduleType,
              batchId: _batchId,
              userId: widget.userId,
              onChanged: _saving ? null : (v) => setState(() => _batchId = v),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _allowNegative,
              onChanged: _saving
                  ? null
                  : (v) => setState(() => _allowNegative = v!),
              title: const Text(
                'Saya mengizinkan stok minus bila stok tidak mencukupi',
              ),
            ),
            const Text(
              'Pemakaian yang sudah dicatat di Logbook tidak perlu dicatat keluar lagi di sini.',
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Menyimpan...' : 'Simpan Mutasi'),
        ),
      ],
    ),
  );
}

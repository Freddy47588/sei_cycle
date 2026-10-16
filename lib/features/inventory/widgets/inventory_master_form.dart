import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../../core/constants/farm_modules.dart';
import '../../../core/widgets/app_ui.dart';
import '../models/inventory_item.dart';
import '../services/inventory_service.dart';

class InventoryMasterForm extends StatefulWidget {
  const InventoryMasterForm({
    required this.service,
    required this.userId,
    this.item,
    super.key,
  });
  final InventoryService service;
  final String userId;
  final InventoryItem? item;
  @override
  State<InventoryMasterForm> createState() => _InventoryMasterFormState();
}

class _InventoryMasterFormState extends State<InventoryMasterForm> {
  final _key = GlobalKey<FormState>();
  final _requestId = const Uuid().v4();
  late final _name = TextEditingController(text: widget.item?.name);
  late final _itemKey = TextEditingController(text: widget.item?.itemKey);
  late final _category = TextEditingController(text: widget.item?.category);
  late final _unit = TextEditingController(text: widget.item?.unit);
  late final _location = TextEditingController(text: widget.item?.location);
  late final _minimum = TextEditingController(
    text: '${widget.item?.minStock ?? 0}',
  );
  final _initial = TextEditingController();
  late String _module = widget.item?.moduleType ?? '';
  bool _saving = false;
  String? _error;
  @override
  void dispose() {
    for (final c in [
      _name,
      _itemKey,
      _category,
      _unit,
      _location,
      _minimum,
      _initial,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_key.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final item = widget.item;
      if (item == null) {
        await widget.service.createItem(
          requestId: _requestId,
          name: _name.text,
          itemKey: _itemKey.text,
          moduleType: _module,
          category: _category.text,
          unit: _unit.text,
          location: _location.text,
          minStock: parseStock(_minimum.text)!,
          initialStock: _initial.text.trim().isEmpty
              ? 0
              : parseStock(_initial.text)!,
          userId: widget.userId,
        );
      } else {
        await widget.service.saveMetadata(
          item: item,
          name: _name.text,
          category: _category.text,
          location: _location.text,
          minStock: parseStock(_minimum.text)!,
          userId: widget.userId,
        );
      }
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
      title: widget.item == null ? 'Tambah Barang' : 'Edit Master Barang',
      maxWidth: 500,
      content: Form(
        key: _key,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (controller, label, locked) in [
              (_name, 'Nama barang', false),
              (_itemKey, 'Item key', widget.item != null),
              (_category, 'Kategori', false),
              (_unit, 'Satuan', widget.item != null),
            ]) ...[
              TextFormField(
                controller: controller,
                enabled: !_saving && !locked,
                decoration: InputDecoration(labelText: label),
                validator: requiredInventoryText,
              ),
              const SizedBox(height: 12),
            ],
            DropdownButtonFormField<String>(
              initialValue: _module,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Modul'),
              items: [
                const DropdownMenuItem(value: '', child: Text('Umum')),
                for (final m in FarmModules.values)
                  DropdownMenuItem(value: m.id, child: Text(m.name)),
              ],
              onChanged: _saving || widget.item != null
                  ? null
                  : (v) => setState(() => _module = v!),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _location,
              enabled: !_saving,
              decoration: const InputDecoration(
                labelText: 'Lokasi penyimpanan (opsional)',
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _minimum,
              enabled: !_saving,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Stok minimum'),
              validator: stockValidator,
            ),
            if (widget.item == null) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _initial,
                enabled: !_saving,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Stok Awal (opsional)',
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? null : stockValidator(v),
              ),
            ] else
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'Jumlah stok berubah melalui Mutasi Stok. Item key, modul, dan satuan tetap untuk menjaga histori.',
                ),
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
          child: Text(_saving ? 'Menyimpan...' : 'Simpan'),
        ),
      ],
    ),
  );
}

double? parseStock(String text) =>
    double.tryParse(text.trim().replaceAll(',', '.'));
String? stockValidator(String? text) {
  final n = parseStock(text ?? '');
  return n == null || !n.isFinite || n < 0 || n > 1e12
      ? 'Masukkan angka 0 sampai 1 triliun'
      : null;
}

String? requiredInventoryText(String? text) =>
    text == null || text.trim().isEmpty ? 'Wajib diisi' : null;

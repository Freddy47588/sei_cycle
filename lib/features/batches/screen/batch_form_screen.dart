import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../../core/constants/farm_modules.dart';
import '../models/cultivation_batch.dart';
import '../services/batch_service.dart';
import '../widgets/batch_card.dart';

class BatchFormScreen extends StatefulWidget {
  const BatchFormScreen({
    required this.service,
    required this.userId,
    this.batch,
    this.initialModule,
    super.key,
  });
  final BatchService service;
  final String userId;
  final CultivationBatch? batch;
  final String? initialModule;
  @override
  State<BatchFormScreen> createState() => _BatchFormScreenState();
}

class _BatchFormScreenState extends State<BatchFormScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name,
      _code,
      _location,
      _quantity,
      _unit,
      _commodity,
      _notes;
  late String _module;
  late DateTime _start;
  DateTime? _harvest;
  bool _saving = false;
  String? _error;
  bool get _editing => widget.batch != null;
  @override
  void initState() {
    super.initState();
    final i = widget.batch?.input;
    _name = TextEditingController(text: i?.name);
    _code = TextEditingController(
      text: i?.code ?? 'B-${const Uuid().v4()}'.toUpperCase(),
    );
    _location = TextEditingController(text: i?.locationName);
    _quantity = TextEditingController(
      text: i?.initialQuantity?.toString() ?? '',
    );
    _unit = TextEditingController(text: i?.initialUnit);
    _commodity = TextEditingController(text: i?.commodity);
    _notes = TextEditingController(text: i?.notes);
    _module =
        i?.moduleType ?? widget.initialModule ?? FarmModules.values.first.id;
    final now = DateTime.now();
    _start = i?.startedAt ?? DateTime(now.year, now.month, now.day);
    _harvest = i?.expectedHarvestAt;
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _code,
      _location,
      _quantity,
      _unit,
      _commodity,
      _notes,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pick(bool harvest) async {
    final d = await showDatePicker(
      context: context,
      initialDate: harvest ? _harvest ?? _start : _start,
      firstDate: DateTime(1900),
      lastDate: DateTime(2200),
    );
    if (d != null && mounted) {
      setState(() {
        if (harvest) {
          _harvest = d;
        } else {
          _start = d;
        }
      });
    }
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final raw = _quantity.text.trim().replaceAll(',', '.');
      final number = raw.isEmpty ? null : double.tryParse(raw);
      if (raw.isNotEmpty && number == null) {
        throw ArgumentError('Jumlah awal tidak valid.');
      }
      final input = BatchInput(
        moduleType: _module,
        name: _name.text,
        code: _code.text,
        locationName: _location.text,
        startedAt: _start,
        expectedHarvestAt: _harvest,
        initialQuantity: number,
        initialUnit: _unit.text,
        commodity: _commodity.text,
        notes: _notes.text,
      );
      input.validate();
      final String savedId;
      if (_editing) {
        await widget.service.edit(
          widget.batch!.id,
          input,
          userId: widget.userId,
          expectedUpdatedAt: widget.batch!.updatedAt!,
        );
        savedId = widget.batch!.id;
      } else {
        savedId = await widget.service.create(input, userId: widget.userId);
      }
      if (mounted) Navigator.pop(context, savedId);
    } catch (e) {
      if (mounted) setState(() => _error = 'Gagal menyimpan: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(
    String label,
    TextEditingController c, {
    bool immutable = false,
    bool required = false,
    bool numeric = false,
    int lines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      controller: c,
      enabled: !_saving && !(_editing && immutable),
      maxLines: lines,
      keyboardType: numeric
          ? const TextInputType.numberWithOptions(decimal: true)
          : lines > 1
          ? TextInputType.multiline
          : TextInputType.text,
      decoration: InputDecoration(labelText: label),
      validator: required
          ? (v) => v == null || v.trim().isEmpty ? 'Wajib diisi' : null
          : null,
    ),
  );
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: Scaffold(
      appBar: AppBar(title: Text(_editing ? 'Edit Batch' : 'Tambah Batch')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _module,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Modul'),
                  items: FarmModules.values
                      .map(
                        (m) =>
                            DropdownMenuItem(value: m.id, child: Text(m.name)),
                      )
                      .toList(),
                  onChanged: _editing || _saving
                      ? null
                      : (v) => setState(() => _module = v!),
                ),
                const SizedBox(height: 16),
                _field('Nama batch', _name, required: true),
                _field(
                  'Kode batch (unik)',
                  _code,
                  required: true,
                  immutable: true,
                ),
                _field(
                  switch (_module) {
                    'lele' => 'Nama / nomor kolam',
                    'ayam_kampung' => 'Kandang / lokasi',
                    'maggot_bsf' => 'Rak / wadah',
                    'cacing_tanah' => 'Lokasi media / bedengan',
                    _ => 'Blok / lahan',
                  },
                  _location,
                  required: true,
                ),
                _field('Komoditas / jenis (opsional)', _commodity),
                OutlinedButton(
                  onPressed: _editing || _saving ? null : () => _pick(false),
                  child: Text('Tanggal mulai: ${batchDate(_start)}'),
                ),
                OutlinedButton(
                  onPressed: _saving ? null : () => _pick(true),
                  child: Text('Estimasi panen: ${batchDate(_harvest)}'),
                ),
                if (_harvest != null)
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => setState(() => _harvest = null),
                    child: const Text('Hapus estimasi panen'),
                  ),
                const SizedBox(height: 16),
                _field(
                  'Jumlah awal (opsional)',
                  _quantity,
                  numeric: true,
                  immutable: true,
                ),
                _field('Unit jumlah awal', _unit, immutable: true),
                const Text(
                  'Contoh unit: ekor, kg, bibit, atau luas sesuai modul.',
                ),
                _field('Catatan tambahan', _notes, lines: 4),
                Text(
                  _editing
                      ? 'Kode, modul, tanggal mulai dan data awal tetap untuk menjaga identitas siklus.'
                      : 'Batch baru berstatus Direncanakan. Aktifkan melalui Detail Batch sebelum dipakai di Logbook.',
                ),
                if (_error != null)
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? 'Menyimpan...' : 'Simpan Batch'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

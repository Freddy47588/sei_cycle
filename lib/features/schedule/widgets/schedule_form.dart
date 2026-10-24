import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../../core/constants/farm_modules.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_ui.dart';
import '../../batches/widgets/operational_batch_picker.dart';
import '../../logbook/services/logbook_service.dart';
import '../models/schedule_item.dart';
import '../services/schedule_service.dart';

class ScheduleForm extends StatefulWidget {
  const ScheduleForm({
    required this.service,
    required this.userId,
    this.item,
    this.logbooks,
    super.key,
  });
  final ScheduleService service;
  final LogbookService? logbooks;
  final String userId;
  final ScheduleItem? item;
  @override
  State<ScheduleForm> createState() => _ScheduleFormState();
}

class _ScheduleFormState extends State<ScheduleForm> {
  final _form = GlobalKey<FormState>();
  final _requestId = const Uuid().v4();
  late final _title = TextEditingController(text: widget.item?.title);
  late final _type = TextEditingController(text: widget.item?.scheduleType);
  late final _note = TextEditingController(text: widget.item?.note);
  late String _module = widget.item?.moduleId ?? FarmModules.ayamKampung.id;
  late String? _batchId = widget.item?.batchId;
  late DateTime _date = widget.item?.scheduledAt ?? DateTime.now();
  bool _saving = false;
  String? _error;
  @override
  void dispose() {
    _title.dispose();
    _type.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_date),
    );
    if (time != null && mounted) {
      setState(
        () => _date = DateTime(
          date.year,
          date.month,
          date.day,
          time.hour,
          time.minute,
        ),
      );
    }
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final id = await widget.service.save(
        id: widget.item?.id,
        requestId: _requestId,
        title: _title.text,
        moduleId: _module,
        scheduleType: _type.text,
        scheduledAt: _date,
        note: _note.text,
        userId: widget.userId,
        batchId: _batchId,
        expectedUpdatedAt: widget.item?.updatedAt,
      );
      if (mounted) Navigator.pop(context, id);
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
      title: widget.item == null ? 'Tambah Jadwal' : 'Edit Jadwal',
      maxWidth: 500,
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              controller: _title,
              enabled: !_saving,
              decoration: const InputDecoration(labelText: 'Judul kegiatan'),
              validator: _required,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _module,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Modul'),
              items: [
                for (final m in FarmModules.values)
                  DropdownMenuItem(value: m.id, child: Text(m.name)),
              ],
              onChanged: _saving
                  ? null
                  : (v) => setState(() {
                      _module = v!;
                      _batchId = null;
                    }),
            ),
            const SizedBox(height: 12),
            OperationalBatchPicker(
              moduleId: _module,
              batchId: _batchId,
              userId: widget.userId,
              service: widget.logbooks,
              onChanged: _saving ? null : (v) => setState(() => _batchId = v),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _type,
              enabled: !_saving,
              decoration: const InputDecoration(labelText: 'Jenis aktivitas'),
              validator: _required,
            ),
            const SizedBox(height: 12),
            AppMenuCard(
              icon: Icons.edit_calendar_outlined,
              title: 'Waktu pelaksanaan (waktu perangkat)',
              subtitle: dateTimeFormat.format(_date),
              onTap: _saving ? null : _pickDate,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _note,
              enabled: !_saving,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Catatan (opsional)',
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Jadwal disimpan sebagai pending. Tandai selesai atau dilewati melalui checklist setelah kegiatan diperiksa.',
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

String? _required(String? text) =>
    text == null || text.trim().isEmpty ? 'Wajib diisi' : null;

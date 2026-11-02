import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../../core/widgets/feature_page.dart';
import '../../profile/models/app_user.dart';
import '../services/admin_management_service.dart';
import '../../batches/screen/batch_list_screen.dart';
import '../../batches/services/batch_service.dart';
import '../../logbook/services/logbook_service.dart';
import '../../logbook/screen/logbook_screen.dart';
import '../../inventory/screen/inventory_screen.dart';
import '../../schedule/screen/schedule_screen.dart';
import '../../finance/screen/finance_screen.dart';
import '../../sales/screen/sales_screen.dart';
import '../../circular_flow/screen/circular_flow_screen.dart';

// Field choices are intentionally explicit. Operational quantities use their source forms.
const adminEditableFields = <String, List<String>>{
  'users': ['name', 'role', 'isActive', 'email'],
  'farm_modules': ['name', 'description', 'isActive'],
  'batches': [
    'name',
    'locationName',
    'notes',
    'commodity',
    'expectedHarvestAt',
  ],
  'logbooks': ['title', 'notes'],
  'inventory': ['name', 'category', 'location', 'minStock'],
  'inventory_items': ['name', 'category', 'location', 'min_stock'],
  'inventory_transactions': ['notes'],
  'production_results': [
    'moduleType',
    'productName',
    'qualityStatus',
    'quantity',
    'unit',
    'harvestDate',
    'notes',
  ],
  'schedules': ['title', 'notes', 'date', 'status', 'type'],
  'finance_transactions': [
    'type',
    'category',
    'amount',
    'date',
    'description',
    'notes',
    'paymentMethod',
  ],
  'finance_records': [
    'type',
    'category',
    'amount',
    'date',
    'description',
    'notes',
  ],
  'sales': ['notes', 'buyerName'],
  'circular_flows': ['materialName', 'quantity', 'unit', 'flowDate', 'notes'],
  'education_contents': [
    'title',
    'summary',
    'content',
    'type',
    'status',
    'moduleType',
    'externalVideoUrl',
    'steps',
    'toolsNeeded',
    'safetyNotes',
    'category',
  ],
  'notifications': ['title', 'body', 'type', 'userId', 'targetRole'],
  'recommendations': [
    'title',
    'description',
    'type',
    'priority',
    'moduleType',
    'isResolved',
  ],
  'report_metadata': ['title', 'description', 'name', 'type'],
};
const _createCategories = {
  'users',
  'farm_modules',
  'production_results',
  'education_contents',
  'notifications',
  'recommendations',
  'report_metadata',
};
const _labels = <String, String>{
  'name': 'Nama',
  'email': 'Email akun baru',
  'description': 'Deskripsi',
  'title': 'Judul',
  'notes': 'Catatan',
  'role': 'Role',
  'isActive': 'Aktif (true/false)',
  'status': 'Status',
  'quantity': 'Jumlah',
  'amount': 'Nominal',
  'unit': 'Satuan',
  'date': 'Tanggal (ISO 8601)',
  'expectedHarvestAt': 'Tanggal rencana panen (ISO 8601)',
  'harvestDate': 'Tanggal panen (ISO 8601)',
  'flowDate': 'Tanggal aliran (ISO 8601)',
  'moduleType': 'Modul',
  'category': 'Kategori',
  'type': 'Jenis',
  'body': 'Pesan',
  'userId': 'UID penerima',
  'targetRole': 'Role penerima',
  'priority': 'Prioritas (high/medium/low)',
  'isResolved': 'Selesai (true/false)',
  'steps': 'Langkah (satu per baris)',
  'toolsNeeded': 'Alat/bahan (satu per baris)',
  'productName': 'Nama hasil',
  'qualityStatus': 'Kualitas',
  'content': 'Isi',
  'summary': 'Ringkasan',
  'externalVideoUrl': 'URL video HTTPS',
  'safetyNotes': 'Keselamatan',
  'materialName': 'Nama bahan',
  'location': 'Lokasi',
  'locationName': 'Nama lokasi',
  'minStock': 'Stok minimum',
  'min_stock': 'Stok minimum legacy',
  'commodity': 'Komoditas',
  'paymentMethod': 'Pembayaran',
  'buyerName': 'Nama pembeli',
};

class AdminManagementScreen extends StatefulWidget {
  const AdminManagementScreen({required this.profile, this.service, super.key});
  final AdminManagementService? service;
  final AppUser profile;
  @override
  State<AdminManagementScreen> createState() => _AdminManagementScreenState();
}

class _AdminManagementScreenState extends State<AdminManagementScreen> {
  late final _service = widget.service ?? AdminManagementService();
  String _category = 'batches', _search = '';
  String? _error;
  bool _loading = false, _more = true;
  final _docs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
  @override
  void initState() {
    super.initState();
    if (widget.profile.isActive && widget.profile.isAdmin) _load();
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) _docs.clear();
    });
    try {
      final page = await _service.page(
        _category,
        after: _docs.isEmpty ? null : _docs.last,
      );
      if (mounted) {
        setState(() {
          _docs.addAll(page.docs);
          _more = page.docs.length == 20;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _manage([
    QueryDocumentSnapshot<Map<String, dynamic>>? doc,
  ]) async {
    final category = _category;
    final command = await showDialog<_Command>(
      context: context,
      builder: (_) => _ManagementForm(category: category, document: doc),
    );
    if (command == null || !mounted) return;
    final previewId = AdminManagementService.newRequestId();
    final executeId = AdminManagementService.newRequestId();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _service.submit(
        requestId: previewId,
        kind: 'preview',
        targetPath: command.path,
        operation: command.operation,
        reason: command.reason,
        patch: command.patch,
      );
      if (!mounted) return;
      setState(() => _loading = false);
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Konfirmasi tindakan Admin'),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${command.operation}: ${command.path}'),
                  const SizedBox(height: 12),
                  Text(result['consequences']?.toString() ?? ''),
                  const SizedBox(height: 12),
                  const Text('Dokumen yang akan berubah:'),
                  for (final change in (result['changes'] as List? ?? []))
                    if (change is Map && change.containsKey('beforeStock'))
                      Text(
                        'Stok: ${change['beforeStock']} menjadi ${change['afterStock']}',
                      ),
                  for (final path in (result['affected'] as List? ?? []))
                    SelectableText('$path'),
                  const SizedBox(height: 12),
                  const Text(
                    'Referensi terkait (tetap dipertahankan kecuali tercantum di atas):',
                  ),
                  for (final path in (result['related'] as List? ?? []))
                    SelectableText('$path'),
                  const SizedBox(height: 12),
                  const Text(
                    'Backup dan audit terlindungi disimpan bersama perubahan. Preview berlaku 10 menit; perubahan data membatalkannya.',
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style:
                  [
                    'delete',
                    'reverse',
                    'softDelete',
                  ].contains(command.operation)
                  ? FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.error,
                    )
                  : null,
              child: const Text('Konfirmasi tindakan'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      setState(() => _loading = true);
      final response = await _service.submit(
        requestId: executeId,
        kind: 'execute',
        previewId: previewId,
        targetPath: command.path,
        operation: command.operation,
        reason: command.reason,
        patch: command.patch,
      );
      if (response['status'] != 'succeeded') {
        throw StateError('Keberhasilan belum terverifikasi.');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tindakan Admin berhasil dan diaudit.')),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        if (_error == null) await _load(reset: true);
      }
    }
  }

  void _openModule() {
    final page = switch (_category) {
      'batches' => BatchListScreen(
        service: BatchService(),
        logbookService: LogbookService(),
        userId: widget.profile.uid,
        canManage: true,
      ),
      'logbooks' => LogbookScreen(profile: widget.profile),
      'inventory' ||
      'inventory_items' ||
      'inventory_transactions' => InventoryScreen(profile: widget.profile),
      'schedules' => ScheduleScreen(profile: widget.profile),
      'finance_transactions' ||
      'finance_records' => FinanceScreen(profile: widget.profile),
      'sales' => SalesScreen(profile: widget.profile),
      'circular_flows' => CircularFlowScreen(profile: widget.profile),
      _ => null,
    };
    if (page != null) {
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            appBar: AppBar(title: const Text('Form operasional')),
            body: page,
          ),
        ),
      );
    }
  }

  void _requestHistory() {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Status permintaan Admin'),
        content: SizedBox(
          width: 560,
          height: 400,
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('admin_requests')
                .where('actorUid', isEqualTo: widget.profile.uid)
                .orderBy('createdAt', descending: true)
                .limit(30)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) return SelectableText('${snapshot.error}');
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              return ListView(
                children: [
                  for (final doc in snapshot.requireData.docs)
                    ListTile(
                      title: Text(
                        '${doc.data()['operation']} ? ${doc.data()['status']}',
                      ),
                      subtitle: SelectableText(
                        '${doc.data()['targetPath']}\nID: ${doc.id}\n${doc.data()['error'] ?? ''}',
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.profile.isActive || !widget.profile.isAdmin) {
      return const Center(child: Text('Akses hanya untuk Admin aktif.'));
    }
    final docs = _docs
        .where(
          (d) => '${d.id} ${d.data()['name'] ?? d.data()['title'] ?? ''}'
              .toLowerCase()
              .contains(_search.toLowerCase()),
        )
        .toList();
    return FeaturePage(
      title: 'Kelola Data Admin',
      subtitle:
          'Periksa dependensi, koreksi, arsipkan, atau hapus catatan dengan audit.',
      actions: [
        IconButton(
          tooltip: 'Status permintaan',
          onPressed: _requestHistory,
          icon: const Icon(Icons.history),
        ),
        if (!_createCategories.contains(_category))
          OutlinedButton(
            onPressed: _loading ? null : _openModule,
            child: const Text('Buka form modul'),
          ),
        IconButton(
          tooltip: 'Muat ulang',
          onPressed: _loading ? null : () => _load(reset: true),
          icon: const Icon(Icons.refresh),
        ),
        if (_createCategories.contains(_category))
          FilledButton.icon(
            onPressed: _loading ? null : () => _manage(),
            icon: const Icon(Icons.add),
            label: const Text('Tambah'),
          ),
      ],
      child: Column(
        children: [
          DropdownButtonFormField<String>(
            initialValue: _category,
            isExpanded: true,
            items: [
              for (final e in adminCategories.entries)
                DropdownMenuItem(value: e.key, child: Text(e.value)),
            ],
            onChanged: _loading
                ? null
                : (value) {
                    setState(() {
                      _category = value!;
                      _docs.clear();
                    });
                    _load(reset: true);
                  },
          ),
          const SizedBox(height: 8),
          TextField(
            decoration: const InputDecoration(
              labelText: 'Cari di halaman yang dimuat',
            ),
            onChanged: (v) => setState(() => _search = v),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: SelectableText(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (_loading) const LinearProgressIndicator(),
          Expanded(
            child: ListView(
              children: [
                if (!_loading && docs.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Tidak ada catatan pada halaman ini.'),
                  ),
                for (final doc in docs)
                  Card(
                    child: ListTile(
                      isThreeLine: true,
                      title: Text(
                        '${doc.data()['name'] ?? doc.data()['title'] ?? doc.data()['productName'] ?? doc.id}',
                      ),
                      subtitle: Text(
                        '${doc.reference.path}\n${doc.data()['status'] ?? (doc.data()['isDeleted'] == true ? 'Dihapus' : 'Tersimpan')}',
                      ),
                      trailing: IconButton(
                        tooltip: 'Lihat dan kelola',
                        onPressed: _loading ? null : () => _manage(doc),
                        icon: const Icon(Icons.manage_search),
                      ),
                    ),
                  ),
                if (_more)
                  TextButton(
                    onPressed: _loading ? null : _load,
                    child: const Text('Muat berikutnya'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Command {
  _Command(this.path, this.operation, this.reason, this.patch);
  final String path, operation, reason;
  final Map<String, dynamic> patch;
}

class _ManagementForm extends StatefulWidget {
  const _ManagementForm({required this.category, this.document});
  final String category;
  final QueryDocumentSnapshot<Map<String, dynamic>>? document;
  @override
  State<_ManagementForm> createState() => _ManagementFormState();
}

class _ManagementFormState extends State<_ManagementForm> {
  final _reason = TextEditingController(), _id = TextEditingController();
  final _fields = <String, TextEditingController>{};
  late String _operation;
  String? _error;
  @override
  void initState() {
    super.initState();
    _operation = widget.document == null ? 'create' : 'update';
    for (final key in adminEditableFields[widget.category]!) {
      final value = widget.document?.data()[key];
      _fields[key] = TextEditingController(
        text: value is Timestamp
            ? value.toDate().toIso8601String()
            : value is List
            ? value.join('\n')
            : value?.toString() ?? '',
      );
    }
  }

  @override
  void dispose() {
    _reason.dispose();
    _id.dispose();
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    try {
      if (_reason.text.trim().length < 5) {
        throw const FormatException('Alasan minimal 5 karakter.');
      }
      final id = widget.document?.id ?? _id.text.trim();
      if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(id)) {
        throw const FormatException(
          'ID wajib diisi tanpa spasi atau garis miring.',
        );
      }
      final patch = <String, dynamic>{};
      if (['create', 'update'].contains(_operation)) {
        for (final e in _fields.entries) {
          final text = e.value.text.trim();
          final old = widget.document?.data()[e.key];
          final oldText = old is Timestamp
              ? old.toDate().toIso8601String()
              : old is List
              ? old.join('\n')
              : old?.toString() ?? '';
          if (widget.document != null && text == oldText) continue;
          if (widget.document == null && text.isEmpty) continue;
          patch[e.key] =
              [
                'quantity',
                'amount',
                'minStock',
                'min_stock',
                'initialQuantity',
              ].contains(e.key)
              ? num.parse(text)
              : ['isActive', 'isResolved', 'isSellable'].contains(e.key)
              ? jsonDecode(text)
              : ['steps', 'toolsNeeded'].contains(e.key)
              ? text.split('\n').where((s) => s.isNotEmpty).toList()
              : text;
        }
        if (patch.isEmpty) throw const FormatException('Belum ada perubahan.');
      }
      Navigator.pop(
        context,
        _Command(
          '${widget.category}/$id',
          _operation,
          _reason.text.trim(),
          patch,
        ),
      );
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.document == null ? 'Tambah catatan' : 'Kelola catatan'),
    content: SizedBox(
      width: 540,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.document == null)
              TextField(
                controller: _id,
                decoration: const InputDecoration(labelText: 'ID unik'),
              ),
            if (widget.document != null) ...[
              SelectableText(widget.document!.reference.path),
              ExpansionTile(
                title: const Text('Rincian catatan'),
                children: [
                  SelectableText(
                    JsonEncoder.withIndent(
                      '  ',
                      (value) => value.toString(),
                    ).convert(
                      _safeReview(widget.document!.data()).map(
                        (k, v) => MapEntry(
                          k,
                          v is Timestamp
                              ? v.toDate().toIso8601String()
                              : v is Map
                              ? v.toString()
                              : v,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              DropdownButtonFormField<String>(
                initialValue: _operation,
                isExpanded: true,
                items: [
                  if (widget.category == 'users')
                    const DropdownMenuItem(
                      value: 'deleteIdentity',
                      child: Text('Hapus profil dan identitas Auth (bertahap)'),
                    ),
                  const DropdownMenuItem(
                    value: 'update',
                    child: Text('Edit / koreksi metadata'),
                  ),
                  DropdownMenuItem(
                    value: 'archive',
                    child: Text('Arsipkan / nonaktifkan'),
                  ),
                  const DropdownMenuItem(
                    value: 'restore',
                    child: Text('Pulihkan catatan yang dihapus lunak'),
                  ),
                  DropdownMenuItem(
                    value: 'softDelete',
                    child: Text('Hapus lunak'),
                  ),
                  DropdownMenuItem(
                    value: 'reverse',
                    child: Text('Batalkan / balikkan efek sumber'),
                  ),
                  DropdownMenuItem(
                    value: 'delete',
                    child: Text('Hapus permanen (setelah dependensi selesai)'),
                  ),
                ],
                onChanged: (v) => setState(() => _operation = v!),
              ),
            ],
            if (['create', 'update'].contains(_operation))
              for (final e in _fields.entries)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: TextField(
                    controller: e.value,
                    minLines: 1,
                    maxLines:
                        [
                          'content',
                          'steps',
                          'notes',
                          'description',
                          'body',
                        ].contains(e.key)
                        ? 5
                        : 1,
                    decoration: InputDecoration(
                      labelText: _labels[e.key] ?? e.key,
                    ),
                  ),
                ),
            const SizedBox(height: 12),
            TextField(
              controller: _reason,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Alasan tindakan Admin (wajib)',
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
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Batal'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Periksa dampak')),
    ],
  );
}

Map<String, dynamic> _safeReview(Map<String, dynamic> data) => {
  for (final e in data.entries)
    if (!RegExp(
      r'password|token|secret|credential|private.?key',
      caseSensitive: false,
    ).hasMatch(e.key))
      e.key: e.value is Map
          ? _safeReview(Map<String, dynamic>.from(e.value as Map))
          : e.value,
};

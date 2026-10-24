import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../utils/legacy_firestore.dart';
import '../../features/profile/models/app_user.dart';
import '../../features/inventory/screen/inventory_screen.dart';
import '../../features/schedule/screen/schedule_screen.dart';
import 'async_state_widgets.dart';

bool canOpenOperationalReference(AppUser user, String collection, String id) =>
    user.isActive &&
    RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(id) &&
    ({
          'inventory',
          'schedules',
          'batches',
          'logbooks',
          'production_results',
          'circular_flows',
        }.contains(collection) ||
        (user.canViewFinance &&
            {'finance_transactions', 'sales'}.contains(collection)));

/// Always reload the exact allowed source; never trust an alert's old body as current data.
class OperationalReferenceScreen extends StatefulWidget {
  const OperationalReferenceScreen({
    required this.profile,
    required this.collection,
    required this.documentId,
    super.key,
  });
  final AppUser profile;
  final String collection, documentId;
  @override
  State<OperationalReferenceScreen> createState() =>
      _OperationalReferenceScreenState();
}

class _OperationalReferenceScreenState
    extends State<OperationalReferenceScreen> {
  late Future<DocumentSnapshot<Map<String, dynamic>>> _future;
  bool get _allowed => canOpenOperationalReference(
    widget.profile,
    widget.collection,
    widget.documentId,
  );
  @override
  void initState() {
    super.initState();
    if (_allowed) _load();
  }

  void _load() {
    _future = FirebaseFirestore.instance
        .collection(widget.collection)
        .doc(widget.documentId)
        .get(const GetOptions(source: Source.server));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Catatan terkait')),
    body: !_allowed
        ? const Center(child: Text('Referensi tidak tersedia untuk akun ini.'))
        : FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return ErrorState(
                  message: '${snapshot.error}',
                  onRetry: () => setState(_load),
                );
              }
              if (!snapshot.hasData) return const LoadingState();
              final data = snapshot.requireData.data();
              if (data == null || !isOperationalRecord(data)) {
                return const EmptyState(
                  title: 'Catatan tidak tersedia',
                  message:
                      'Referensi telah dihapus, diarsipkan, atau tidak lagi operasional.',
                  icon: Icons.link_off,
                );
              }
              return ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  SelectableText('${widget.collection}/${widget.documentId}'),
                  const SizedBox(height: 16),
                  for (final field in const {
                    'title': 'Judul',
                    'name': 'Nama',
                    'productName': 'Hasil',
                    'status': 'Status',
                    'notes': 'Catatan',
                    'description': 'Deskripsi',
                    'quantity': 'Jumlah',
                    'unit': 'Satuan',
                    'currentStock': 'Stok tercatat',
                  }.entries)
                    if (data[field.key] != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: SelectableText(
                          '${field.value}: ${data[field.key]}',
                        ),
                      ),
                  if (widget.collection == 'schedules' ||
                      widget.collection == 'inventory')
                    FilledButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => widget.collection == 'schedules'
                              ? ScheduleScreen(profile: widget.profile)
                              : InventoryScreen(profile: widget.profile),
                        ),
                      ),
                      child: const Text('Buka pengelolaan modul'),
                    ),
                ],
              );
            },
          ),
  );
}

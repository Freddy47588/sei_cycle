import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../../core/models/firestore_page.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/operation_error.dart';
import '../../../core/widgets/app_ui.dart';
import '../../../core/widgets/firestore_paged_list.dart';
import '../../profile/models/app_user.dart';
import '../models/finance_record.dart';

class FinanceDetailScreen extends StatefulWidget {
  const FinanceDetailScreen({
    required this.id,
    required this.profile,
    this.firestore,
    super.key,
  });
  final String id;
  final AppUser profile;
  final FirebaseFirestore? firestore;
  @override
  State<FinanceDetailScreen> createState() => _FinanceDetailScreenState();
}

class _FinanceDetailScreenState extends State<FinanceDetailScreen> {
  late final _db = widget.firestore ?? FirebaseFirestore.instance;
  late Future<DocumentSnapshot<Map<String, dynamic>>> _future;
  @override
  void initState() {
    super.initState();
    if (widget.profile.canViewFinance) _load();
  }

  void _load() {
    _future = _db.collection('finance_transactions').doc(widget.id).get();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.profile.canViewFinance) {
      return const Scaffold(body: Center(child: Text('Akses ditolak.')));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Histori Transaksi')),
      body: FutureBuilder(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: TextButton(
                onPressed: () => setState(_load),
                child: Text(operationError(snap.error!)),
              ),
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snap.requireData.exists) {
            return const Center(child: Text('Transaksi tidak ditemukan.'));
          }
          final r = FinanceRecord.fromDocument(snap.requireData);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.category),
                      Text(currencyFormat.format(r.amount)),
                      Text(shortDateFormat.format(r.date)),
                      Text(
                        '${r.type == "income" ? "Pemasukan" : "Pengeluaran"} · ${r.paymentMethod}',
                      ),
                      Text(r.notes),
                      Text(
                        'Pembuat: ${r.createdBy} · Pengubah: ${r.updatedBy}',
                      ),
                      if (r.isDeleted)
                        const Text(
                          'Dihapus dari laporan; audit dipertahankan.',
                        ),
                      if (r.isSaleLinked)
                        SelectableText('Penjualan terkait: ${r.saleId}'),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: FirestorePagedList<Map<String, dynamic>>(
                  queryKey: widget.id,
                  load: (cursor) async {
                    var q = _db
                        .collection('finance_transactions')
                        .doc(widget.id)
                        .collection('edits')
                        .orderBy('editedAt', descending: true)
                        .limit(20);
                    if (cursor != null) q = q.startAfterDocument(cursor);
                    final p = await q.get();
                    return FirestorePage(
                      p.docs.map((d) => d.data()).toList(),
                      p.docs.lastOrNull,
                      p.docs.length == 20,
                    );
                  },
                  itemBuilder: (d) => AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Petugas: ${d["editedBy"]}'),
                        Text(
                          'Nominal: ${currencyFormat.format(d["before"]["amount"])} → ${currencyFormat.format(d["after"]["amount"])}',
                        ),
                        Text(
                          'Kategori: ${d["before"]["category"]} → ${d["after"]["category"]}',
                        ),
                        Text(
                          'Catatan: ${d["before"]["notes"] ?? ""} → ${d["after"]["notes"] ?? ""}',
                        ),
                        if (d['after']['isDeleted'] == true)
                          const Text('Dihapus dari laporan'),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

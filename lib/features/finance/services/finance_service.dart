import '../../../core/constants/farm_modules.dart';
import '../../../core/utils/sample_data_guard.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import 'dart:convert';
import '../../../core/models/firestore_page.dart';
import '../../../core/utils/operational_auth.dart';
import '../../profile/models/app_user.dart';

import '../../../core/constants/firestore_collections.dart';
import '../../../core/utils/firestore_validators.dart';
import '../models/finance_record.dart';

class FinanceService {
  FinanceService({FirebaseFirestore? firestore, Uuid? uuid})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _uuid = uuid ?? const Uuid();

  final FirebaseFirestore _firestore;
  final Uuid _uuid;

  static const _validTypes = {'income', 'expense'};

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection(FirestoreCollections.financeTransactions);

  Stream<List<FinanceRecord>> watchRecords() {
    return _collection
        .where('isDeleted', isEqualTo: false)
        .orderBy('date', descending: true)
        .limit(100)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs.map(FinanceRecord.fromDocument).toList(),
        );
  }

  Future<FinanceSummary> loadCurrentMonthSummary({DateTime? now}) {
    final anchor = now ?? DateTime.now();
    final start = DateTime(anchor.year, anchor.month);
    final end = DateTime(anchor.year, anchor.month + 1);
    return loadSummaryByDateRange(start: start, end: end);
  }

  Future<FinanceSummary> loadSummaryByDateRange({
    required DateTime start,
    required DateTime end,
    String? type,
    String? category,
    String? moduleType,
  }) async {
    _validateDateRange(start: start, end: end);
    await requireNoSampleData(_firestore, ['finance_transactions']);
    final snapshot = await _query(
      start: start,
      end: end,
      type: type,
      category: category,
      moduleType: moduleType,
    ).limit(501).get();
    if (snapshot.docs.length > 500) {
      throw StateError(
        'Lebih dari 500 transaksi. Persempit periode/filter untuk ringkasan lengkap.',
      );
    }
    for (final doc in snapshot.docs) {
      final d = doc.data();
      if (d['amount'] is! num ||
          !(d['amount'] as num).isFinite ||
          (d['amount'] as num) <= 0 ||
          !_validTypes.contains(d['type'])) {
        throw StateError(
          'Transaksi tidak valid. Ringkasan memerlukan pemeriksaan pengelola.',
        );
      }
    }
    return cashflowSummary(
      snapshot.docs.map(FinanceRecord.fromDocument),
      start: start,
      end: end,
    );
  }

  FinanceSummary monthlyProfitLossFromRecords(
    Iterable<FinanceRecord> records, {
    DateTime? now,
  }) {
    final anchor = now ?? DateTime.now();
    return monthlyProfitLoss(records, month: anchor);
  }

  Query<Map<String, dynamic>> _query({
    required DateTime start,
    required DateTime end,
    String? type,
    String? category,
    String? moduleType,
  }) {
    _validateDateRange(start: start, end: end);
    Query<Map<String, dynamic>> q = _collection
        .where('isDeleted', isEqualTo: false)
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('date', isLessThan: Timestamp.fromDate(end));
    if (type != null) q = q.where('type', isEqualTo: type);
    if (category != null) q = q.where('category', isEqualTo: category);
    if (moduleType != null) q = q.where('moduleType', isEqualTo: moduleType);
    return q.orderBy('date', descending: true);
  }

  Future<FirestorePage<FinanceRecord>> fetchPage({
    required DateTime start,
    required DateTime end,
    String? type,
    String? category,
    String? moduleType,
    DocumentSnapshot<Map<String, dynamic>>? cursor,
  }) async {
    var q = _query(
      start: start,
      end: end,
      type: type,
      category: category,
      moduleType: moduleType,
    ).limit(20);
    if (cursor != null) q = q.startAfterDocument(cursor);
    final page = await q.get();
    return FirestorePage(
      page.docs.map(FinanceRecord.fromDocument).toList(),
      page.docs.lastOrNull,
      page.docs.length == 20,
    );
  }

  Future<AppUser> _authorize(Transaction tx, String uid) async {
    final doc = await tx.get(_firestore.collection('users').doc(uid));
    if (!doc.exists || !AppUser.fromDocument(doc).canManageFinance) {
      throw StateError('Tidak memiliki izin keuangan.');
    }
    return AppUser.fromDocument(doc);
  }

  Future<void> save({
    String? id,
    String? requestId,
    DateTime? expectedUpdatedAt,
    required String type,
    required String category,
    required double amount,
    required DateTime date,
    required String note,
    String paymentMethod = '',
    String moduleType = '',
    required String userId,
  }) async {
    final normalizedType = type.trim().toLowerCase();
    _validateSave(
      type: normalizedType,
      category: category,
      amount: amount,
      date: date,
      userId: userId,
    );
    if (!{
      '',
      ...FarmModules.values.map((m) => m.id),
    }.contains(moduleType.trim())) {
      throw ArgumentError('Modul keuangan tidak valid.');
    }
    final rid = requestId ?? _uuid.v4();
    validateDocumentId(rid);
    final documentId = id ?? rid;
    validateDocumentId(documentId);
    final fields = <String, dynamic>{
      'type': normalizedType,
      'category': category.trim(),
      'amount': amount,
      'date': Timestamp.fromDate(date),
      'description': note.trim(),
      'notes': note.trim(),
      'paymentMethod': paymentMethod.trim(),
      'moduleType': moduleType.trim(),
      'isDeleted': false,
    };
    final payload = jsonEncode([
      normalizedType,
      category.trim(),
      amount,
      date.microsecondsSinceEpoch,
      note.trim(),
      paymentMethod.trim(),
      moduleType.trim(),
      userId,
    ]);
    final ref = _collection.doc(documentId);
    await runOperationalTransaction(_firestore, (tx) async {
      await _authorize(tx, userId);
      final prior = await tx.get(ref);
      final now = FieldValue.serverTimestamp();
      if (id == null) {
        if (prior.exists) {
          if (prior.data()?['creationPayload'] != payload ||
              prior.data()?['createdBy'] != userId) {
            throw StateError('Request ID sama dengan payload berbeda.');
          }
          return;
        }
        tx.set(ref, {
          ...fields,
          'id': documentId,
          'requestId': rid,
          'creationPayload': payload,
          'source': 'manual',
          'version': 0,
          'createdBy': userId,
          'updatedBy': userId,
          'createdAt': now,
          'updatedAt': now,
        });
      } else {
        final d = prior.data();
        final auditRef = ref.collection('edits').doc(rid);
        final audit = await tx.get(auditRef);
        if (audit.exists) {
          if (audit.data()?['payload'] != payload ||
              audit.data()?['editedBy'] != userId) {
            throw StateError('Request ID sama dengan payload berbeda.');
          }
          return;
        }
        if (!prior.exists ||
            d?['isDeleted'] != false ||
            (d?['saleId'] != null && d?['saleId'] != '') ||
            d?['source'] == 'sale') {
          throw StateError(
            'Transaksi terintegrasi atau terhapus tidak dapat diedit manual.',
          );
        }
        if (expectedUpdatedAt == null ||
            FinanceRecord.fromDocument(prior).updatedAt != expectedUpdatedAt) {
          throw StateError(
            'Transaksi telah berubah. Muat ulang sebelum mengedit.',
          );
        }
        final after = {
          ...d!,
          ...fields,
          'version': (d['version'] as int? ?? 0) + 1,
          'lastEditId': rid,
          'updatedBy': userId,
          'updatedAt': now,
        };
        tx.set(auditRef, {
          'before': d,
          'after': after,
          'payload': payload,
          'editedBy': userId,
          'editedAt': now,
        });
        tx.set(ref, after);
      }
    });
  }

  Future<void> delete(
    String id, {
    required String userId,
    required DateTime expectedUpdatedAt,
    required String requestId,
  }) async {
    validateDocumentId(id);
    validateDocumentId(requestId);
    final ref = _collection.doc(id);
    await runOperationalTransaction(_firestore, (tx) async {
      await _authorize(tx, userId);
      final old = await tx.get(ref);
      final d = old.data();
      final auditRef = ref.collection('edits').doc(requestId);
      final audit = await tx.get(auditRef);
      if (audit.exists &&
          audit.data()?['payload'] == 'delete' &&
          audit.data()?['editedBy'] == userId) {
        return;
      }
      if (!old.exists ||
          d?['source'] == 'sale' ||
          (d?['saleId'] != null && d?['saleId'] != '') ||
          d?['isDeleted'] != false ||
          FinanceRecord.fromDocument(old).updatedAt != expectedUpdatedAt ||
          audit.exists) {
        throw StateError(
          'Transaksi berubah atau terintegrasi. Penghapusan manual ditolak.',
        );
      }
      final now = FieldValue.serverTimestamp();
      final after = {
        ...d!,
        'isDeleted': true,
        'version': (d['version'] as int? ?? 0) + 1,
        'lastEditId': requestId,
        'updatedBy': userId,
        'updatedAt': now,
      };
      tx.set(auditRef, {
        'before': d,
        'after': after,
        'payload': 'delete',
        'editedBy': userId,
        'editedAt': now,
      });
      tx.set(ref, after);
    });
  }

  void _validateSave({
    required String type,
    required String category,
    required double amount,
    required DateTime date,
    required String userId,
  }) {
    requireOneOf(type, _validTypes, 'type');
    requireTrimmed(category, 'category');
    requirePositive(amount, 'amount');
    if (!amount.isFinite || amount > 1e12) {
      throw ArgumentError('Nominal harus finite dan maksimal Rp1 triliun.');
    }
    _requireValidDate(date, 'date');
    requireTrimmed(userId, 'userId');
  }

  static FinanceSummary monthlyProfitLoss(
    Iterable<FinanceRecord> records, {
    required DateTime month,
  }) {
    final start = DateTime(month.year, month.month);
    final end = DateTime(month.year, month.month + 1);
    return cashflowSummary(records, start: start, end: end);
  }

  static FinanceSummary cashflowSummary(
    Iterable<FinanceRecord> records, {
    required DateTime start,
    required DateTime end,
  }) {
    _validateDateRange(start: start, end: end);
    final activeRecords = records.where((record) {
      return !record.isDeleted &&
          !record.date.isBefore(start) &&
          record.date.isBefore(end);
    }).toList();

    final byCategory = <String, FinanceCategorySummary>{};
    var totalIncome = 0.0;
    var totalExpense = 0.0;

    for (final record in activeRecords) {
      if (record.type == 'income') {
        totalIncome += record.amount;
      } else if (record.type == 'expense') {
        totalExpense += record.amount;
      }

      final key = record.category.trim().isEmpty
          ? 'Tanpa kategori'
          : record.category.trim();
      byCategory[key] = (byCategory[key] ?? FinanceCategorySummary.empty(key))
          .add(record);
    }

    return FinanceSummary(
      start: start,
      end: end,
      totalIncome: totalIncome,
      totalExpense: totalExpense,
      byCategory: Map.unmodifiable(byCategory),
      transactions: List.unmodifiable(activeRecords),
    );
  }

  static void _validateDateRange({
    required DateTime start,
    required DateTime end,
  }) {
    _requireValidDate(start, 'start');
    _requireValidDate(end, 'end');
    if (!end.isAfter(start)) {
      throw ArgumentError.value(end, 'end', 'end harus setelah start.');
    }
  }

  static void _requireValidDate(DateTime value, String fieldName) {
    if (value.year < 1900 || value.year > 2200) {
      throw ArgumentError.value(value, fieldName, '$fieldName tidak valid.');
    }
  }
}

class FinanceSummary {
  const FinanceSummary({
    required this.start,
    required this.end,
    required this.totalIncome,
    required this.totalExpense,
    required this.byCategory,
    required this.transactions,
  });

  final DateTime start;
  final DateTime end;
  final double totalIncome;
  final double totalExpense;
  final Map<String, FinanceCategorySummary> byCategory;
  final List<FinanceRecord> transactions;

  double get netProfit => totalIncome - totalExpense;
}

class FinanceCategorySummary {
  const FinanceCategorySummary({
    required this.category,
    required this.income,
    required this.expense,
    required this.count,
  });

  factory FinanceCategorySummary.empty(String category) {
    return FinanceCategorySummary(
      category: category,
      income: 0,
      expense: 0,
      count: 0,
    );
  }

  final String category;
  final double income;
  final double expense;
  final int count;

  double get netProfit => income - expense;

  FinanceCategorySummary add(FinanceRecord record) {
    return FinanceCategorySummary(
      category: category,
      income: income + (record.type == 'income' ? record.amount : 0),
      expense: expense + (record.type == 'expense' ? record.amount : 0),
      count: count + 1,
    );
  }
}

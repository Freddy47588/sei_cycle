import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/utils/firestore_fields.dart';
import '../../../core/utils/operational_auth.dart';

const salePaymentMethods = ['tunai', 'transfer', 'qris'];

/// Quantities have at most three decimals; Rupiah rounds half up once per sale.
class SaleInput {
  const SaleInput({
    required this.inventoryItemId,
    required this.quantity,
    required this.unit,
    required this.unitPrice,
    required this.saleDate,
    required this.paymentMethod,
    this.buyerName = '',
    this.notes = '',
  });
  final String inventoryItemId, unit, paymentMethod, buyerName, notes;
  final double quantity;
  final int unitPrice;
  final DateTime saleDate;
  int get quantityMilli => (quantity * 1000).round();
  int get totalAmount => (quantityMilli * unitPrice / 1000).round();
  void validate() {
    validateDocumentId(inventoryItemId);
    if (!quantity.isFinite ||
        quantity <= 0 ||
        quantity > 1e6 ||
        (quantity * 1000 - quantityMilli).abs() > 0.000001 ||
        unitPrice <= 0 ||
        unitPrice > 1000000000 ||
        totalAmount <= 0 ||
        totalAmount > 1000000000000 ||
        unit.trim().isEmpty ||
        !salePaymentMethods.contains(paymentMethod) ||
        saleDate.year < 2020 ||
        saleDate.year > 2100) {
      throw ArgumentError(
        'Periksa jumlah (maksimal 3 desimal), harga Rupiah, tanggal, satuan dan pembayaran.',
      );
    }
  }

  String payload(String actor) => jsonEncode([
    inventoryItemId,
    quantityMilli,
    unit.trim(),
    unitPrice,
    saleDate.microsecondsSinceEpoch,
    paymentMethod,
    buyerName.trim(),
    notes.trim(),
    actor,
  ]);
}

class Sale {
  const Sale({
    this.createdByName = '',
    required this.id,
    required this.saleNumber,
    required this.inventoryItemId,
    required this.productName,
    required this.moduleType,
    required this.quantity,
    required this.unit,
    required this.unitPrice,
    required this.totalAmount,
    required this.saleDate,
    required this.paymentMethod,
    required this.buyerName,
    required this.notes,
    required this.createdBy,
    required this.inventoryTransactionId,
    required this.financeTransactionId,
    required this.status,
    required this.createdAt,
  });
  final String createdByName;
  final String id,
      saleNumber,
      inventoryItemId,
      productName,
      moduleType,
      unit,
      paymentMethod,
      buyerName,
      notes,
      createdBy,
      inventoryTransactionId,
      financeTransactionId,
      status;
  final double quantity;
  final int unitPrice, totalAmount;
  final DateTime saleDate, createdAt;
  factory Sale.fromDocument(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return Sale(
      createdByName: stringField(d, const [
        'createdByName',
      ], fallback: stringField(d, const ['createdBy'])),
      id: doc.id,
      saleNumber: stringField(d, const ['saleNumber']),
      inventoryItemId: stringField(d, const ['inventoryItemId']),
      productName: stringField(d, const ['productName']),
      moduleType: stringField(d, const ['moduleType']),
      quantity: doubleField(d, const ['quantity']),
      unit: stringField(d, const ['unit']),
      unitPrice: (d['unitPrice'] as num).toInt(),
      totalAmount: (d['totalAmount'] as num).toInt(),
      saleDate: dateTimeField(d, const ['saleDate']),
      paymentMethod: stringField(d, const ['paymentMethod']),
      buyerName: stringField(d, const ['buyerName']),
      notes: stringField(d, const ['notes']),
      createdBy: stringField(d, const ['createdBy']),
      createdAt: dateTimeField(d, const ['createdAt']),
      inventoryTransactionId: stringField(d, const ['inventoryTransactionId']),
      financeTransactionId: stringField(d, const ['financeTransactionId']),
      status: stringField(d, const ['status']),
    );
  }
}

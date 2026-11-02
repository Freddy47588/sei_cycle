import '../../sales/models/sale.dart';
import '../../circular_flow/models/circular_flow.dart';
import '../../finance/models/finance_record.dart';
import '../../inventory/models/inventory_item.dart';
import '../../logbook/models/logbook_entry.dart';

class AnalyticsModel {
  AnalyticsModel({
    this.sales = const [],
    this.circularFlows = const [],
    this.financeIncluded = false,
    required this.logbooks,
    required this.inventoryItems,
    required this.financeRecords,
    required this.startDate,
    required this.endDate,
  });

  final List<Sale> sales;
  final List<CircularFlow> circularFlows;
  final bool financeIncluded;
  int get totalSales => sales.fold(0, (sum, s) => sum + s.totalAmount);
  Map<String, int> get salesPerProduct => _salesBy((s) => s.productName);
  Map<String, int> get salesPerModule => _salesBy((s) => s.moduleType);
  Map<String, int> _salesBy(String Function(Sale) group) {
    final result = <String, int>{};
    for (final s in sales) {
      result.update(
        group(s),
        (v) => v + s.totalAmount,
        ifAbsent: () => s.totalAmount,
      );
    }
    return result;
  }

  Map<String, double> get flowsPerMaterial {
    final result = <String, double>{};
    for (final f in circularFlows.where((f) => f.isActual)) {
      final key = '${f.materialName} (${f.unit})';
      result.update(key, (v) => v + f.quantity, ifAbsent: () => f.quantity);
    }
    return result;
  }

  final List<LogbookEntry> logbooks;
  final List<InventoryItem> inventoryItems;
  final List<FinanceRecord> financeRecords;
  final DateTime startDate;
  final DateTime endDate;

  // Analytics Helpers
  Map<String, int> get logbooksPerModule {
    final map = <String, int>{};
    for (final log in logbooks) {
      final module = log.moduleId;
      if (module.isNotEmpty) {
        map[module] = (map[module] ?? 0) + 1;
      }
    }
    return map;
  }

  List<InventoryItem> get lowStockItems {
    return inventoryItems
        .where((item) => item.currentStock <= item.minStock)
        .toList();
  }

  double get totalIncome {
    return financeRecords
        .where((record) => record.type == 'income')
        .fold(0.0, (sum, record) => sum + record.amount);
  }

  double get totalExpense {
    return financeRecords
        .where((record) => record.type == 'expense')
        .fold(0.0, (sum, record) => sum + record.amount);
  }

  double get profitLoss => totalIncome - totalExpense;
}

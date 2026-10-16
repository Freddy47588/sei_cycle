import 'package:flutter/material.dart';

class DashboardActivity {
  const DashboardActivity({
    required this.time,
    required this.title,
    required this.icon,
    required this.color,
    required this.done,
    this.id = '',
    this.source = 'logbook',
    this.moduleType = '',
    this.status = 'recorded',
    this.batchId,
    this.occurredAt,
  });

  final String time;
  final String title;
  final IconData icon;
  final Color color;
  final bool done;
  final String id, source, moduleType, status;
  final String? batchId;
  final DateTime? occurredAt;
}

class RevenueBreakdownItem {
  const RevenueBreakdownItem({
    required this.label,
    required this.amount,
    required this.portion,
    required this.color,
  });

  final String label;
  final double amount;
  final double portion;
  final Color color;
}

class LowStockDashboardItem {
  const LowStockDashboardItem({
    required this.id,
    required this.name,
    required this.currentStock,
    required this.minStock,
    required this.unit,
  });

  final String id;
  final String name;
  final double currentStock;
  final double minStock;
  final String unit;
}

class DashboardCircularFlow {
  const DashboardCircularFlow({
    required this.sourceModuleType,
    required this.destinationModuleType,
    required this.materialName,
    required this.quantity,
    required this.unit,
    required this.notes,
    this.flowDate,
  });

  final String sourceModuleType;
  final String destinationModuleType;
  final String materialName;
  final double quantity;
  final String unit;
  final String notes;
  final DateTime? flowDate;
}

class DashboardSummary {
  const DashboardSummary({
    this.salesTotal,
    this.soldQuantities = const {},
    this.salesError,
    required this.activeModuleCount,
    required this.todayLogCount,
    required this.todayScheduleCount,
    required this.lowStockCount,
    required this.monthlyIncome,
    required this.monthlyExpense,
    required this.monthlyProfit,
    required this.recentActivities,
    required this.revenueItems,
    required this.circularFlows,
    required this.lowStockPreview,
    required this.financeVisible,
    this.activeBatchCount = 0,
    this.completedBatchCount = 0,
    this.pendingScheduleCount = 0,
    this.doneScheduleCount = 0,
    this.skippedScheduleCount = 0,
    this.outOfStockCount = 0,
    this.inventoryLoaded = 0,
    this.inventoryTruncated = false,
    this.financeError,
    this.updatedAt,
  });

  final int? salesTotal;
  final Map<String, double> soldQuantities;
  final Object? salesError;
  final int activeModuleCount;
  final int todayLogCount;
  final int todayScheduleCount;
  final int lowStockCount;
  final double monthlyIncome;
  final double monthlyExpense;
  final double monthlyProfit;
  final List<DashboardActivity> recentActivities;
  final List<RevenueBreakdownItem> revenueItems;
  final List<DashboardCircularFlow> circularFlows;
  final List<LowStockDashboardItem> lowStockPreview;
  final bool financeVisible;
  final int activeBatchCount, completedBatchCount;
  final int pendingScheduleCount, doneScheduleCount, skippedScheduleCount;
  final int outOfStockCount, inventoryLoaded;
  final bool inventoryTruncated;
  final Object? financeError;
  final DateTime? updatedAt;

  bool get hasFinanceData => monthlyIncome > 0 || monthlyExpense > 0;
}

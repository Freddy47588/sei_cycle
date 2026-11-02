enum ReportType { operational, finance, inventory, fullSummary }

class ReportFilter {
  ReportFilter({
    required this.startDate,
    required this.endDate,
    this.moduleType,
    this.reportType = ReportType.fullSummary,
  });

  DateTime startDate;
  DateTime endDate;
  String? moduleType;
  ReportType reportType;

  ReportFilter copyWith({
    DateTime? startDate,
    DateTime? endDate,
    String? moduleType,
    ReportType? reportType,
  }) {
    return ReportFilter(
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      moduleType: moduleType ?? this.moduleType,
      reportType: reportType ?? this.reportType,
    );
  }
}

double? finiteNumber(Object? value) {
  final number = value is num
      ? value.toDouble()
      : value is String
      ? double.tryParse(value.trim().replaceAll(',', '.'))
      : null;
  return number != null && number.isFinite ? number : null;
}

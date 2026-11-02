import 'package:intl/intl.dart';

final DateFormat shortDateFormat = DateFormat('dd MMM yyyy', 'id_ID');
final DateFormat dateTimeFormat = DateFormat('dd MMM yyyy, HH:mm', 'id_ID');
final DateFormat timeFormat = DateFormat('HH:mm', 'id_ID');
final NumberFormat currencyFormat = NumberFormat.currency(
  locale: 'id_ID',
  symbol: 'Rp ',
  decimalDigits: 0,
);

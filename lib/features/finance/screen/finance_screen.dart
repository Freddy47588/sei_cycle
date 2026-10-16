import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../../core/widgets/firestore_paged_list.dart';
import '../../../core/widgets/period_filter.dart';
import '../../../core/utils/operation_error.dart';

import '../../../core/constants/farm_modules.dart';

import '../../../core/utils/delete_confirmation.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/operation_feedback.dart';
import '../../../core/widgets/app_ui.dart';
import '../../../core/widgets/async_state_widgets.dart';
import '../../../core/widgets/feature_page.dart';
import '../../../theme/app_theme.dart';
import '../../profile/models/app_user.dart';
import '../models/finance_record.dart';
import 'finance_detail_screen.dart';
import '../services/finance_service.dart';

class FinanceScreen extends StatefulWidget {
  const FinanceScreen({required this.profile, this.service, super.key});
  final FinanceService? service;

  final AppUser profile;

  @override
  State<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends State<FinanceScreen> {
  late final _service = widget.service ?? FinanceService();
  DateTimeRange _period = monthPeriod();
  String? _type, _module, _category;
  String _search = '';
  int _revision = 0;
  late Future<FinanceSummary> _summary;
  @override
  void initState() {
    super.initState();
    if (widget.profile.canViewFinance) _reloadSummary();
  }

  void _reloadSummary() {
    _summary = _service.loadSummaryByDateRange(
      start: _period.start,
      end: _period.end,
      type: _type,
      category: _category,
      moduleType: _module,
    );
  }

  void _refresh() => setState(() {
    _revision++;
    _reloadSummary();
  });
  Future<void> _openForm([FinanceRecord? record]) async {
    if (!widget.profile.canManageFinance || (record?.isSaleLinked ?? false)) {
      return;
    }
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => FinanceFormDialog(
        record: record,
        service: _service,
        userId: widget.profile.uid,
      ),
    );
    if (saved == true && mounted) {
      _refresh();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Transaksi tersimpan.')));
    }
  }

  Future<void> _delete(FinanceRecord record) async {
    final confirmed = await confirmDelete(
      context,
      title: 'Hapus transaksi?',
      message:
          'Transaksi ${record.category} sebesar ${currencyFormat.format(record.amount)} dikeluarkan dari laporan. Histori audit tetap disimpan.',
    );
    if (!confirmed || !mounted) return;
    await runOperationWithFeedback(
      context,
      operation: () => _service.delete(
        record.id,
        userId: widget.profile.uid,
        expectedUpdatedAt: record.updatedAt,
        requestId: const Uuid().v4(),
      ),
      successMessage: 'Transaksi dihapus dari laporan.',
    );
    if (mounted) _refresh();
  }

  Future<void> _detail(FinanceRecord r) => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => FinanceDetailScreen(id: r.id, profile: widget.profile),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (!widget.profile.canViewFinance) {
      return const Center(child: Text('Tidak memiliki akses keuangan.'));
    }
    return FeaturePage(
      title: 'Keuangan',
      subtitle: 'Pemasukan - Pengeluaran = Arus Kas Bersih',
      actions: [
        IconButton(
          onPressed: _refresh,
          tooltip: 'Muat ulang',
          icon: const Icon(Icons.refresh),
        ),
        if (widget.profile.canManageFinance)
          FilledButton.icon(
            onPressed: _openForm,
            icon: const Icon(Icons.add),
            label: const Text('Tambah transaksi'),
          ),
      ],
      child: Column(
        children: [
          Expanded(
            child: FirestorePagedList<FinanceRecord>(
              header: Column(
                children: [
                  ExpansionTile(
                    title: const Text('Periode dan filter'),
                    children: [
                      PeriodFilter(
                        value: _period,
                        onChanged: (v) {
                          _period = v;
                          _refresh();
                        },
                      ),
                      DropdownButtonFormField<String>(
                        initialValue: _type ?? '',
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Jenis transaksi',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: '',
                            child: Text('Semua jenis'),
                          ),
                          DropdownMenuItem(
                            value: 'income',
                            child: Text('Pemasukan'),
                          ),
                          DropdownMenuItem(
                            value: 'expense',
                            child: Text('Pengeluaran'),
                          ),
                        ],
                        onChanged: (v) {
                          _type = v == '' ? null : v;
                          _refresh();
                        },
                      ),
                      DropdownButtonFormField<String>(
                        initialValue: '',
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Modul'),
                        items: [
                          const DropdownMenuItem(
                            value: '',
                            child: Text('Semua modul'),
                          ),
                          for (final m in FarmModules.values)
                            DropdownMenuItem(value: m.id, child: Text(m.name)),
                        ],
                        onChanged: (v) {
                          _module = v == '' ? null : v;
                          _refresh();
                        },
                      ),
                      TextField(
                        decoration: const InputDecoration(
                          labelText: 'Kategori transaksi',
                          helperText:
                              'Tekan Enter untuk menerapkan kategori lengkap.',
                        ),
                        onSubmitted: (v) {
                          _category = v.trim().isEmpty ? null : v.trim();
                          _refresh();
                        },
                      ),
                      TextField(
                        decoration: const InputDecoration(
                          labelText: 'Cari kategori atau catatan',
                          helperText:
                              'Pencarian pada transaksi yang sudah dimuat; ringkasan mengikuti periode dan filter.',
                          helperMaxLines: 4,
                        ),
                        onChanged: (v) =>
                            setState(() => _search = v.toLowerCase()),
                      ),
                    ],
                  ),
                  FutureBuilder<FinanceSummary>(
                    key: ObjectKey(_summary),
                    future: _summary,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return ErrorState(
                          message: operationError(snapshot.error!),
                          onRetry: _refresh,
                        );
                      }
                      if (!snapshot.hasData) return const LoadingState();
                      final r = snapshot.requireData;
                      return Column(
                        children: [
                          if (r.transactions.isEmpty)
                            const Text(
                              'Belum ada transaksi pada periode dan filter ini.',
                            ),
                          _FinanceSummary(
                            income: r.totalIncome,
                            expense: r.totalExpense,
                            balance: r.netProfit,
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
              queryKey: '$_revision',
              load: (cursor) => _service.fetchPage(
                start: _period.start,
                end: _period.end,
                type: _type,
                category: _category,
                moduleType: _module,
                cursor: cursor,
              ),
              transform: (rows) => rows
                  .where(
                    (r) => '${r.category} ${r.notes}'.toLowerCase().contains(
                      _search,
                    ),
                  )
                  .toList(),
              itemBuilder: (r) => InkWell(
                onTap: () => _detail(r),
                child: _FinanceRecordCard(
                  record: r,
                  canEdit: widget.profile.canManageFinance && !r.isSaleLinked,
                  canDelete: widget.profile.canDeleteFinance && !r.isSaleLinked,
                  onEdit: () => _openForm(r),
                  onDelete: () => _delete(r),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FinanceSummary extends StatelessWidget {
  const _FinanceSummary({
    required this.income,
    required this.expense,
    required this.balance,
  });

  final double income;
  final double expense;
  final double balance;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 820
            ? 3
            : constraints.maxWidth >= 520
            ? 2
            : 1;
        const spacing = 10.0;
        final width =
            (constraints.maxWidth - ((columns - 1) * spacing)) / columns;
        final cards = [
          _FinanceTotalCard(
            label: 'Pemasukan periode terpilih',
            value: income,
            color: AppColors.success,
            icon: Icons.south_west_rounded,
          ),
          _FinanceTotalCard(
            label: 'Pengeluaran periode terpilih',
            value: expense,
            color: AppColors.error,
            icon: Icons.north_east_rounded,
          ),
          _FinanceTotalCard(
            label: 'Arus Kas Bersih',
            value: balance,
            color: balance >= 0 ? AppColors.primaryGreen : AppColors.warning,
            icon: Icons.account_balance_wallet_outlined,
          ),
        ];
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final card in cards) SizedBox(width: width, child: card),
          ],
        );
      },
    );
  }
}

class _FinanceTotalCard extends StatelessWidget {
  const _FinanceTotalCard({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  final String label;
  final double value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          AppIconBox(icon: icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    currencyFormat.format(value),
                    style: Theme.of(
                      context,
                    ).textTheme.titleLarge?.copyWith(color: color),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FinanceRecordCard extends StatelessWidget {
  const _FinanceRecordCard({
    required this.record,
    required this.canEdit,
    required this.canDelete,
    required this.onEdit,
    required this.onDelete,
  });

  final FinanceRecord record;
  final bool canEdit;
  final bool canDelete;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final isIncome = record.type == 'income';
    final color = isIncome ? AppColors.success : AppColors.error;
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppIconBox(
            icon: isIncome
                ? Icons.south_west_rounded
                : Icons.north_east_rounded,
            color: color,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        record.category,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    const SizedBox(width: 8),
                    StatusBadge(
                      label: isIncome ? 'Pemasukan' : 'Pengeluaran',
                      color: color,
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  shortDateFormat.format(record.date),
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: AppColors.textMuted),
                ),
                if (record.paymentMethod.trim().isNotEmpty ||
                    record.moduleType.trim().isNotEmpty) ...[
                  const SizedBox(height: 7),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (record.paymentMethod.trim().isNotEmpty)
                        StatusBadge(
                          label: record.paymentMethod,
                          color: AppColors.primaryGreen,
                        ),
                      if (record.moduleType.trim().isNotEmpty)
                        StatusBadge(
                          label: FarmModules.nameOf(record.moduleType),
                          color: AppColors.info,
                        ),
                    ],
                  ),
                ],
                if (record.note.trim().isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    record.note,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
                const SizedBox(height: 9),
                Row(
                  children: [
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          currencyFormat.format(record.amount),
                          style: Theme.of(
                            context,
                          ).textTheme.titleLarge?.copyWith(color: color),
                        ),
                      ),
                    ),
                    if (canEdit || canDelete)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (canEdit)
                            IconButton(
                              onPressed: onEdit,
                              icon: const Icon(Icons.edit_outlined, size: 19),
                              tooltip: 'Edit transaksi',
                            ),
                          if (canDelete)
                            IconButton(
                              onPressed: onDelete,
                              icon: const Icon(
                                Icons.delete_outline,
                                size: 19,
                                color: AppColors.error,
                              ),
                              tooltip: 'Hapus transaksi',
                            ),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class FinanceFormDialog extends StatefulWidget {
  const FinanceFormDialog({
    this.record,
    required this.service,
    required this.userId,
    super.key,
  });
  final FinanceService service;
  final String userId;

  final FinanceRecord? record;

  @override
  State<FinanceFormDialog> createState() => FinanceFormDialogState();
}

class FinanceFormDialogState extends State<FinanceFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _requestId = const Uuid().v4();
  bool _saving = false;
  String? _error;
  late final TextEditingController _category;
  late final TextEditingController _amount;
  late final TextEditingController _note;
  late final TextEditingController _paymentMethod;
  late String _moduleType;
  late String _type;
  late DateTime _date;

  @override
  void initState() {
    super.initState();
    final record = widget.record;
    _category = TextEditingController(text: record?.category);
    _amount = TextEditingController(
      text: record == null ? '' : record.amount.toString(),
    );
    _note = TextEditingController(text: record?.note);
    _paymentMethod = TextEditingController(text: record?.paymentMethod);
    _moduleType = record?.moduleType ?? '';
    _type = record?.type ?? 'income';
    _date = record?.date ?? DateTime.now();
  }

  @override
  void dispose() {
    _category.dispose();
    _amount.dispose();
    _note.dispose();
    _paymentMethod.dispose();
    super.dispose();
  }

  double? _parsedAmount() =>
      double.tryParse(_amount.text.trim().replaceAll(',', '.'));

  Future<void> _submit() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.service.save(
        id: widget.record?.id,
        requestId: _requestId,
        expectedUpdatedAt: widget.record?.updatedAt,
        type: _type,
        category: _category.text,
        amount: _parsedAmount()!,
        date: _date,
        note: _note.text,
        paymentMethod: _paymentMethod.text,
        moduleType: _moduleType,
        userId: widget.userId,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = operationError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_saving,
      child: AppDialogShell(
        title: widget.record == null ? 'Tambah Transaksi' : 'Edit Transaksi',
        maxWidth: 480,
        content: AbsorbPointer(
          absorbing: _saving,
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_error != null)
                  Text(_error!, style: const TextStyle(color: AppColors.error)),
                DropdownButtonFormField<String>(
                  initialValue: _type,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Jenis transaksi',
                  ),
                  items: const [
                    DropdownMenuItem(value: 'income', child: Text('Pemasukan')),
                    DropdownMenuItem(
                      value: 'expense',
                      child: Text('Pengeluaran'),
                    ),
                  ],
                  onChanged: (value) => setState(() => _type = value!),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _category,
                  decoration: const InputDecoration(
                    labelText: 'Kategori',
                    hintText: 'Contoh: penjualan telur',
                  ),
                  validator: _required,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _amount,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Nominal',
                    prefixText: 'Rp ',
                  ),
                  validator: (_) {
                    final value = _parsedAmount();
                    return value == null ||
                            !value.isFinite ||
                            value > 1e12 ||
                            value <= 0
                        ? 'Nominal harus lebih dari 0'
                        : null;
                  },
                ),
                const SizedBox(height: 12),
                AppMenuCard(
                  icon: Icons.calendar_today_outlined,
                  title: 'Tanggal transaksi',
                  subtitle: shortDateFormat.format(_date),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () async {
                    final result = await showDatePicker(
                      context: context,
                      initialDate: _date,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (result != null) setState(() => _date = result);
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _paymentMethod,
                  decoration: const InputDecoration(
                    labelText: 'Metode pembayaran',
                    hintText: 'Contoh: tunai, transfer, QRIS',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _moduleType,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Modul kebun'),
                  items: [
                    DropdownMenuItem(value: '', child: Text('Umum')),
                    for (final module in FarmModules.values)
                      DropdownMenuItem(
                        value: module.id,
                        child: Text(module.name),
                      ),
                  ],
                  onChanged: (value) {
                    setState(() => _moduleType = value ?? '');
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _note,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Catatan',
                    hintText: 'Keterangan singkat transaksi (opsional)',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: _saving ? null : _submit,
            child: Text(_saving ? 'Menyimpan...' : 'Simpan'),
          ),
        ],
      ),
    );
  }
}

String? _required(String? value) =>
    value == null || value.trim().isEmpty ? 'Wajib diisi' : null;

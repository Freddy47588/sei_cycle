import 'package:flutter/material.dart';
import '../../../core/constants/farm_modules.dart';
import '../../../core/utils/delete_confirmation.dart';
import '../../../core/utils/operation_feedback.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_ui.dart';
import '../../../core/widgets/feature_page.dart';
import '../../../core/widgets/firestore_paged_list.dart';
import '../../../theme/app_theme.dart';
import '../../profile/models/app_user.dart';
import '../../notification/services/notification_service.dart';
import '../models/inventory_item.dart';
import '../services/inventory_service.dart';
import '../services/inventory_adjustment_service.dart';
import '../widgets/inventory_master_form.dart';
import '../widgets/inventory_transaction_form.dart';
import 'inventory_history_screen.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({
    required this.profile,
    this.service,
    this.adjustments,
    this.notifications,
    super.key,
  });
  final AppUser profile;
  final InventoryService? service;
  final InventoryAdjustmentService? adjustments;
  final NotificationService? notifications;
  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  late final _service = widget.service ?? InventoryService();
  final _search = TextEditingController(), _category = TextEditingController();
  String _module = '', _categoryFilter = '', _stock = 'all', _sort = 'name';
  int _revision = 0;
  @override
  void dispose() {
    _search.dispose();
    _category.dispose();
    super.dispose();
  }

  Future<void> _form([InventoryItem? item]) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => InventoryMasterForm(
        service: _service,
        userId: widget.profile.uid,
        item: item,
      ),
    );
    if (saved == true && mounted) setState(() => _revision++);
  }

  Future<void> _mutate(InventoryItem item) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => InventoryTransactionForm(
        item: item,
        userId: widget.profile.uid,
        service: widget.adjustments ?? InventoryAdjustmentService(),
      ),
    );
    if (saved == true && mounted) setState(() => _revision++);
  }

  void _history([InventoryItem? item]) => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => InventoryHistoryScreen(
        userId: widget.profile.uid,
        canEdit: widget.profile.canManageLogbooks,
        field: item == null ? null : 'itemId',
        value: item?.id,
      ),
    ),
  );
  Future<void> _delete(InventoryItem item) async {
    if (!await confirmDelete(
          context,
          title: 'Hapus master barang?',
          message: 'Stok harus nol. Seluruh histori dipertahankan.',
        ) ||
        !mounted) {
      return;
    }
    await runOperationWithFeedback(
      context,
      operation: () => _service.delete(item.id, userId: widget.profile.uid),
      successMessage: 'Master barang dihapus.',
    );
    if (mounted) setState(() => _revision++);
  }

  List<InventoryItem> _visible(List<InventoryItem> rows) {
    rows = rows.where((item) => !item.isDeleted).toList();
    final text = _search.text.trim().toLowerCase();
    rows = rows
        .where(
          (i) =>
              '${i.name} ${i.itemKey} ${i.location}'.toLowerCase().contains(
                text,
              ) &&
              switch (_stock) {
                'safe' => i.currentStock > i.minStock,
                'low' => i.currentStock > 0 && i.currentStock <= i.minStock,
                'empty' => i.currentStock <= 0,
                _ => true,
              },
        )
        .toList();
    rows.sort(
      (a, b) => switch (_sort) {
        'stock' => a.currentStock.compareTo(b.currentStock),
        'updated' => b.updatedAt.compareTo(a.updatedAt),
        _ => a.name.compareTo(b.name),
      },
    );
    return rows;
  }

  @override
  Widget build(BuildContext context) => FeaturePage(
    title: 'Inventaris',
    subtitle: 'Persediaan lokasi, mutasi stok, dan histori Kebun Sei.',
    actions: [
      OutlinedButton.icon(
        onPressed: _history,
        icon: const Icon(Icons.history),
        label: const Text('Riwayat Mutasi'),
      ),
      if (widget.profile.canManageInventory)
        FilledButton.icon(
          onPressed: _form,
          icon: const Icon(Icons.add),
          label: const Text('Tambah Barang'),
        ),
      IconButton(
        onPressed: () => setState(() => _revision++),
        tooltip: 'Muat ulang stok',
        icon: const Icon(Icons.refresh),
      ),
    ],
    child: Column(
      children: [
        TextField(
          controller: _search,
          decoration: const InputDecoration(
            labelText: 'Cari nama, item key, lokasi pada data dimuat',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('Filter & urutan'),
          children: [
            ResponsiveFormRow(
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _module,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Modul'),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('Semua Modul'),
                    ),
                    for (final m in FarmModules.values)
                      DropdownMenuItem(value: m.id, child: Text(m.name)),
                  ],
                  onChanged: (v) => setState(() => _module = v!),
                ),
                TextField(
                  controller: _category,
                  decoration: InputDecoration(
                    labelText: 'Kategori (persis)',
                    suffixIcon: IconButton(
                      tooltip: 'Terapkan kategori',
                      onPressed: () => setState(
                        () => _categoryFilter = _category.text.trim(),
                      ),
                      icon: const Icon(Icons.check),
                    ),
                  ),
                  onSubmitted: (v) =>
                      setState(() => _categoryFilter = v.trim()),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ResponsiveFormRow(
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _stock,
                  decoration: const InputDecoration(
                    labelText: 'Status stok dimuat',
                  ),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('Semua Barang')),
                    DropdownMenuItem(value: 'safe', child: Text('Stok Aman')),
                    DropdownMenuItem(value: 'low', child: Text('Stok Rendah')),
                    DropdownMenuItem(value: 'empty', child: Text('Stok Habis')),
                  ],
                  onChanged: (v) => setState(() => _stock = v!),
                ),
                DropdownButtonFormField<String>(
                  initialValue: _sort,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Urutkan data dimuat',
                  ),
                  items: const [
                    DropdownMenuItem(value: 'name', child: Text('Nama A-Z')),
                    DropdownMenuItem(
                      value: 'stock',
                      child: Text('Stok terkecil'),
                    ),
                    DropdownMenuItem(
                      value: 'updated',
                      child: Text('Baru diperbarui'),
                    ),
                  ],
                  onChanged: (v) => setState(() => _sort = v!),
                ),
              ],
            ),
          ],
        ),
        Expanded(
          child: FirestorePagedList<InventoryItem>(
            idOf: (item) => item.id,
            queryKey: (_module, _categoryFilter, _revision),
            load: (cursor) => _service.fetchPage(
              moduleType: _module.isEmpty ? null : _module,
              category: _categoryFilter.isEmpty ? null : _categoryFilter,
              cursor: cursor,
            ),
            transform: _visible,
            watchPage: _service.watchLoaded,
            onLoaded: widget.profile.canManageInventory
                ? (items) => (widget.notifications ?? NotificationService())
                      .createLowStockAlerts(
                        userId: widget.profile.uid,
                        role: widget.profile.effectiveRole,
                        items: items,
                      )
                : null,
            itemBuilder: (item) => AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  StatusBadge(
                    label: item.currentStock <= 0
                        ? 'Stok Habis'
                        : item.isLowStock
                        ? 'Stok Rendah'
                        : 'Stok Aman',
                    color: item.currentStock <= 0
                        ? AppColors.error
                        : item.isLowStock
                        ? AppColors.warning
                        : AppColors.success,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${item.currentStock} ${item.unit}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text(
                    'Minimum ${item.minStock} ${item.unit} \u00b7 ${item.category}',
                  ),
                  Text(
                    item.moduleType.isEmpty
                        ? 'Modul umum'
                        : FarmModules.nameOf(item.moduleType),
                  ),
                  if (item.location.isNotEmpty)
                    Text('Lokasi: ${item.location}'),
                  Text('Diperbarui: ${dateTimeFormat.format(item.updatedAt)}'),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton.icon(
                        onPressed: () => _history(item),
                        icon: const Icon(Icons.history),
                        label: const Text('Histori'),
                      ),
                      if (widget.profile.canManageInventory) ...[
                        TextButton(
                          onPressed: () => _form(item),
                          child: const Text('Edit Master'),
                        ),
                        FilledButton.tonal(
                          onPressed: () => _mutate(item),
                          child: const Text('Mutasi Stok'),
                        ),
                      ],
                      if (widget.profile.canDeleteInventory)
                        IconButton(
                          onPressed: () => _delete(item),
                          tooltip: 'Hapus master barang',
                          icon: const Icon(Icons.delete_outline),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

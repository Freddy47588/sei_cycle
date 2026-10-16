import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/delete_confirmation.dart';
import '../../../core/utils/operation_feedback.dart';
import '../../../theme/app_theme.dart';
import '../../inventory/services/inventory_service.dart';
import '../../profile/models/app_user.dart';
import '../models/logbook_entry.dart';
import '../services/logbook_service.dart';

class LogbookScreen extends StatefulWidget {
  const LogbookScreen({required this.profile, this.service, super.key});
  final LogbookService? service;

  final AppUser profile;

  @override
  State<LogbookScreen> createState() => _LogbookScreenState();
}

class _LogbookScreenState extends State<LogbookScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  static const _tabs = [
    _TabInfo('Ayam', Icons.egg_alt_outlined),
    _TabInfo('Maggot', Icons.bug_report_outlined),
    _TabInfo('Cacing', Icons.grass_outlined),
    _TabInfo('Tanaman', Icons.eco_outlined),
    _TabInfo('Lele', Icons.water_drop_outlined),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _LogbookHeader(tabController: _tabController, tabs: _tabs),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              AyamModule(
                userId: widget.profile.uid,
                canDeleteHistory: widget.profile.canDeleteLogbooks,
                canSave: widget.profile.canManageLogbooks,
                service: widget.service,
              ),
              MaggotModule(
                userId: widget.profile.uid,
                canDeleteHistory: widget.profile.canDeleteLogbooks,
                canSave: widget.profile.canManageLogbooks,
                service: widget.service,
              ),
              CacingModule(
                userId: widget.profile.uid,
                canDeleteHistory: widget.profile.canDeleteLogbooks,
                canSave: widget.profile.canManageLogbooks,
                service: widget.service,
              ),
              TanamanModule(
                userId: widget.profile.uid,
                canDeleteHistory: widget.profile.canDeleteLogbooks,
                canSave: widget.profile.canManageLogbooks,
                service: widget.service,
              ),
              LeleModule(
                userId: widget.profile.uid,
                canDeleteHistory: widget.profile.canDeleteLogbooks,
                canSave: widget.profile.canManageLogbooks,
                service: widget.service,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TabInfo {
  const _TabInfo(this.label, this.icon);

  final String label;
  final IconData icon;
}

class _LogbookHeader extends StatelessWidget {
  const _LogbookHeader({required this.tabController, required this.tabs});

  final TabController tabController;
  final List<_TabInfo> tabs;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Logbook Operasional',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'Catat aktivitas harian setiap modul budidaya',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          TabBar(
            controller: tabController,
            isScrollable: true,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            tabs: tabs
                .map(
                  (t) => Tab(
                    height: 48,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(t.icon, size: 16),
                        const SizedBox(width: 6),
                        Text('Modul ${t.label}'),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
          const Divider(height: 1),
        ],
      ),
    );
  }
}

class _FormCard extends StatelessWidget {
  const _FormCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.children,
  });

  final String title;
  final IconData icon;
  final Color color;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(
                      context,
                    ).textTheme.titleLarge?.copyWith(color: color),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }
}

Widget _buildField(
  String label,
  String hint, {
  TextInputType type = TextInputType.text,
  String? suffix,
  int maxLines = 1,
  String? initialValue,
  ValueChanged<String>? onChanged,
}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextFormField(
      initialValue: initialValue,
      keyboardType: maxLines > 1 ? TextInputType.multiline : type,
      scrollPadding: const EdgeInsets.only(bottom: 100),
      textInputAction: maxLines == 1
          ? TextInputAction.next
          : TextInputAction.newline,
      maxLines: maxLines,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        suffix: suffix != null
            ? Text(
                suffix,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              )
            : null,
      ),
    ),
  );
}

Widget _buildResponsiveFormRow(List<Widget> fields, double maxWidth) {
  if (maxWidth >= 600) {
    return Wrap(
      spacing: 16,
      runSpacing: 0,
      children: fields
          .map((field) => SizedBox(width: (maxWidth - 56) / 2, child: field))
          .toList(),
    );
  }
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: fields,
  );
}

Widget _buildSubmitRow({
  required VoidCallback onHistory,
  required VoidCallback? onSubmit,
  required bool saving,
}) {
  return LayoutBuilder(
    builder: (context, constraints) {
      final stacked =
          constraints.maxWidth < 360 ||
          MediaQuery.textScalerOf(context).scale(1) > 1.2;
      final history = OutlinedButton.icon(
        onPressed: saving ? null : onHistory,
        icon: const Icon(Icons.history_outlined, size: 18),
        label: const Text('Lihat Riwayat'),
      );
      final save = ElevatedButton.icon(
        onPressed: saving ? null : onSubmit,
        icon: saving
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.save_outlined, size: 18),
        label: Text(saving ? 'Menyimpan...' : 'Simpan Catatan'),
      );
      if (stacked) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [history, const SizedBox(height: 12), save],
        );
      }
      return Row(
        children: [
          Expanded(child: history),
          const SizedBox(width: 12),
          Expanded(child: save),
        ],
      );
    },
  );
}

class AyamModule extends StatefulWidget {
  const AyamModule({
    required this.userId,
    required this.canDeleteHistory,
    this.canSave = true,
    this.service,
    super.key,
  });

  final String userId;
  final bool canDeleteHistory;
  final bool canSave;
  final LogbookService? service;

  @override
  State<AyamModule> createState() => _AyamModuleState();
}

class _AyamModuleState extends _ModuleFormState<AyamModule> {
  @override
  _ModuleSpec get spec => _ayamSpec;

  @override
  String get userId => widget.userId;

  @override
  bool get canDeleteHistory => widget.canDeleteHistory;

  @override
  bool get canSave => widget.canSave;

  @override
  LogbookService? get injectedService => widget.service;
}

class MaggotModule extends StatefulWidget {
  const MaggotModule({
    required this.userId,
    required this.canDeleteHistory,
    this.canSave = true,
    this.service,
    super.key,
  });

  final String userId;
  final bool canDeleteHistory;
  final bool canSave;
  final LogbookService? service;

  @override
  State<MaggotModule> createState() => _MaggotModuleState();
}

class _MaggotModuleState extends _ModuleFormState<MaggotModule> {
  @override
  _ModuleSpec get spec => _maggotSpec;

  @override
  String get userId => widget.userId;

  @override
  bool get canDeleteHistory => widget.canDeleteHistory;

  @override
  bool get canSave => widget.canSave;

  @override
  LogbookService? get injectedService => widget.service;
}

class CacingModule extends StatefulWidget {
  const CacingModule({
    required this.userId,
    required this.canDeleteHistory,
    this.canSave = true,
    this.service,
    super.key,
  });

  final String userId;
  final bool canDeleteHistory;
  final bool canSave;
  final LogbookService? service;

  @override
  State<CacingModule> createState() => _CacingModuleState();
}

class _CacingModuleState extends _ModuleFormState<CacingModule> {
  @override
  _ModuleSpec get spec => _cacingSpec;

  @override
  String get userId => widget.userId;

  @override
  bool get canDeleteHistory => widget.canDeleteHistory;

  @override
  bool get canSave => widget.canSave;

  @override
  LogbookService? get injectedService => widget.service;
}

class TanamanModule extends StatefulWidget {
  const TanamanModule({
    required this.userId,
    required this.canDeleteHistory,
    this.canSave = true,
    this.service,
    super.key,
  });

  final String userId;
  final bool canDeleteHistory;
  final bool canSave;
  final LogbookService? service;

  @override
  State<TanamanModule> createState() => _TanamanModuleState();
}

class _TanamanModuleState extends _ModuleFormState<TanamanModule> {
  @override
  _ModuleSpec get spec => _tanamanSpec;

  @override
  String get userId => widget.userId;

  @override
  bool get canDeleteHistory => widget.canDeleteHistory;

  @override
  bool get canSave => widget.canSave;

  @override
  LogbookService? get injectedService => widget.service;
}

class LeleModule extends StatefulWidget {
  const LeleModule({
    required this.userId,
    required this.canDeleteHistory,
    this.canSave = true,
    this.service,
    super.key,
  });

  final String userId;
  final bool canDeleteHistory;
  final bool canSave;
  final LogbookService? service;

  @override
  State<LeleModule> createState() => _LeleModuleState();
}

class _LeleModuleState extends _ModuleFormState<LeleModule> {
  @override
  _ModuleSpec get spec => _leleSpec;

  @override
  String get userId => widget.userId;

  @override
  bool get canDeleteHistory => widget.canDeleteHistory;

  @override
  bool get canSave => widget.canSave;

  @override
  LogbookService? get injectedService => widget.service;
}

abstract class _ModuleFormState<T extends StatefulWidget> extends State<T> {
  late final _service = injectedService ?? LogbookService();
  final _values = <String, String>{};
  bool _saving = false;
  double? _sliderValue;

  _ModuleSpec get spec;
  String get userId;
  bool get canDeleteHistory;
  bool get canSave;
  LogbookService? get injectedService;

  @override
  void initState() {
    super.initState();
    _sliderValue = null;
    for (final section in spec.sections) {
      for (final field in section.fields) {
        _values[field.key] = '';
      }
    }
  }

  Future<void> _submit() async {
    if (!canSave) return;
    if (_values.values.every((value) => value.trim().isEmpty)) {
      _showMessage('Isi hasil pengamatan sebelum menyimpan catatan.');
      return;
    }
    if (userId.trim().isEmpty) {
      _showMessage('User belum terdeteksi. Silakan login ulang.');
      return;
    }

    setState(() => _saving = true);
    try {
      final details = <String, dynamic>{};
      for (final entry in _values.entries) {
        details[entry.key] = _typedValue(entry.value);
      }
      final warnings = await _service.previewInventoryStockWarnings(
        moduleType: spec.moduleType,
        details: details,
      );
      if (warnings.isNotEmpty && mounted) {
        final confirmed = await _confirmNegativeStock(warnings);
        if (!confirmed) {
          setState(() => _saving = false);
          return;
        }
      }
      await _service.createDailyEntry(
        moduleType: spec.moduleType,
        title: spec.title,
        activityType: spec.activityType,
        quantity: _doubleValue(spec.quantityKey),
        unit: spec.quantityUnit,
        notes: _values[spec.notesKey]?.trim(),
        details: details,
        userId: userId,
      );
      if (!mounted) return;
      _showMessage('Catatan ${spec.label} berhasil disimpan.');
    } catch (error) {
      if (!mounted) return;
      _showMessage('Gagal menyimpan catatan: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _confirmNegativeStock(
    List<InventoryStockWarning> warnings,
  ) async {
    final message = warnings
        .map(
          (warning) =>
              '${warning.itemName}: stok ${_number(warning.currentStock)} ${warning.unit}, keluar ${_number(warning.requestedQuantity)} ${warning.unit}, sisa ${_number(warning.afterStock)} ${warning.unit}.',
        )
        .join('\n');
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Stok tidak mencukupi'),
            content: Text(
              'Beberapa stok akan menjadi minus. Tetap simpan catatan?\n\n$message',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Batal'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Tetap Simpan'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _openHistory() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) => _HistorySheet(
        service: _service,
        spec: spec,
        userId: userId,
        canDelete: canDeleteHistory,
      ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  double? _doubleValue(String? key) {
    if (key == null) return null;
    return double.tryParse((_values[key] ?? '').replaceAll(',', '.'));
  }

  Object? _typedValue(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';
    return double.tryParse(trimmed.replaceAll(',', '.')) ?? trimmed;
  }

  List<_BannerStat> _bannerStats() {
    String value(String key, String unit, {String fallback = '-'}) {
      final raw = (_values[key] ?? '').trim();
      if (raw.isEmpty) return fallback;
      return unit.isEmpty ? raw : '$raw $unit';
    }

    return switch (spec.moduleType) {
      'ayam_kampung' => [
        _BannerStat('Populasi', value('populasi_aktif', 'ekor')),
        _BannerStat(
          'Produksi Hari Ini',
          value('produksi_telur_hari_ini', 'butir'),
        ),
        _BannerStat('Mortalitas', value('mortalitas_hari_ini', 'ekor')),
      ],
      'maggot_bsf' => [
        _BannerStat('Limbah Masuk', value('volume_limbah_masuk_kg', 'kg')),
        _BannerStat(
          'Fase Larva',
          value('fase_larva_hari', 'hari', fallback: 'Belum diisi'),
        ),
        _BannerStat('Est. Panen', value('estimasi_panen_kg', 'kg')),
      ],
      'cacing_tanah' => [
        _BannerStat('Media', value('media_cacing_kg', 'kg')),
        _BannerStat('Kelembaban', value('kelembapan_media_persen', '%')),
        _BannerStat('Kascing', value('panen_kascing_kg', 'kg')),
      ],
      'tanaman' => [
        _BannerStat('Komoditas', value('jenis_tanaman', '')),
        _BannerStat('Usia', value('usia_tanaman', 'hari')),
        _BannerStat('Pupuk', value('pupuk_kascing_cair_liter', 'L/m2')),
      ],
      'lele' => [
        _BannerStat('Tebar Benih', value('jumlah_ikan', 'ekor')),
        _BannerStat('Survival Rate', value('kondisi_air', '%')),
        _BannerStat('Pakan/Hari', value('pakan_lele_kg', 'kg')),
      ],
      _ => const [],
    };
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Column(
        children: [
          _ModuleBanner(
            label: spec.bannerLabel,
            desc: 'Catat hasil pengamatan aktual ${spec.label.toLowerCase()}.',
            icon: spec.icon,
            color: spec.color,
            stats: _bannerStats(),
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, c) {
              return Column(
                children: [
                  for (final section in spec.sections)
                    _FormCard(
                      title: section.title,
                      icon: section.icon,
                      color: section.color,
                      children: [
                        for (
                          var index = 0;
                          index < section.fields.length;
                          index += 2
                        )
                          _buildResponsiveFormRow(
                            section.fields
                                .skip(index)
                                .take(2)
                                .map(
                                  (field) => _buildField(
                                    field.label,
                                    field.hint,
                                    type: field.type,
                                    suffix: field.suffix,
                                    maxLines: field.maxLines,
                                    initialValue: '',
                                    onChanged: (value) => setState(
                                      () => _values[field.key] = value,
                                    ),
                                  ),
                                )
                                .toList(),
                            c.maxWidth,
                          ),
                        if (section == spec.sections.first &&
                            spec.slider != null)
                          _SliderInput(
                            spec: spec.slider!,
                            value: _sliderValue ?? spec.slider!.min,
                            hasValue: _sliderValue != null,
                            onChanged: (value) {
                              setState(() => _sliderValue = value);
                              _values[spec.slider!.key] = value.toStringAsFixed(
                                0,
                              );
                            },
                          ),
                        if (section == spec.sections.first &&
                            spec.moduleType == 'maggot_bsf' &&
                            _sliderValue != null)
                          _PhaseBadge(hari: (_sliderValue ?? 12).toInt()),
                      ],
                    ),
                  _buildSubmitRow(
                    onHistory: _openHistory,
                    onSubmit: canSave ? _submit : null,
                    saving: _saving,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SliderInput extends StatelessWidget {
  const _SliderInput({
    required this.spec,
    required this.value,
    required this.hasValue,
    required this.onChanged,
  });

  final _SliderSpec spec;
  final double value;
  final bool hasValue;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            children: [
              Text(
                '${spec.label}: ',
                style: const TextStyle(
                  color: AppColors.textMedium,
                  fontSize: 13,
                ),
              ),
              Text(
                hasValue ? '${value.toInt()} ${spec.unit}' : 'Belum diisi',
                style: TextStyle(
                  color: spec.color,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          Slider(
            value: value,
            min: spec.min,
            max: spec.max,
            divisions: (spec.max - spec.min).round(),
            activeColor: spec.color,
            inactiveColor: spec.color.withValues(alpha: 0.2),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _PhaseBadge extends StatelessWidget {
  const _PhaseBadge({required this.hari});

  final int hari;

  @override
  Widget build(BuildContext context) {
    String phase;
    Color color;
    if (hari <= 3) {
      phase = 'Fase Telur -> Instar 1 (1-3 hari)';
      color = AppColors.info;
    } else if (hari <= 7) {
      phase = 'Fase Instar Awal (4-7 hari) - pertumbuhan aktif';
      color = AppColors.accentLightGreen;
    } else if (hari <= 12) {
      phase = 'Fase Instar Akhir (8-12 hari) - feeding masif';
      color = AppColors.warning;
    } else {
      phase = 'Prepupa (13-14 hari) - SIAP PANEN';
      color = AppColors.success;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: color, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              phase,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HistorySheet extends StatefulWidget {
  const _HistorySheet({
    required this.service,
    required this.spec,
    required this.userId,
    required this.canDelete,
  });

  final LogbookService service;
  final _ModuleSpec spec;
  final String userId;
  final bool canDelete;

  @override
  State<_HistorySheet> createState() => _HistorySheetState();
}

class _HistorySheetState extends State<_HistorySheet> {
  late Future<List<LogbookEntry>> _historyFuture;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _historyFuture = widget.service.getHistoryByModule(widget.spec.moduleType);
  }

  Future<void> _delete(LogbookEntry entry) async {
    final confirmed = await confirmDelete(
      context,
      title: 'Hapus riwayat?',
      message: 'Catatan "${entry.title}" akan dihapus dari riwayat logbook.',
    );
    if (!confirmed || !mounted) return;

    final success = await runOperationWithFeedback(
      context,
      operation: () =>
          widget.service.softDelete(entry.id, userId: widget.userId),
      successMessage: 'Riwayat logbook dihapus.',
    );
    if (!success || !mounted) return;
    setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (context, controller) {
        return FutureBuilder<List<LogbookEntry>>(
          future: _historyFuture,
          builder: (context, snapshot) {
            final entries = snapshot.data ?? const <LogbookEntry>[];
            return ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              children: [
                Text(
                  'Riwayat ${widget.spec.label}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                if (snapshot.connectionState != ConnectionState.done)
                  const Center(child: CircularProgressIndicator())
                else if (snapshot.hasError)
                  Text(
                    'Riwayat gagal dimuat: ${snapshot.error}',
                    style: const TextStyle(color: AppColors.error),
                  )
                else if (entries.isEmpty)
                  const Text(
                    'Belum ada catatan tersimpan.',
                    style: TextStyle(color: AppColors.textMuted),
                  )
                else
                  for (final entry in entries) ...[
                    _HistoryCard(
                      entry: entry,
                      spec: widget.spec,
                      canDelete: widget.canDelete,
                      onDelete: () => _delete(entry),
                    ),
                    const SizedBox(height: 10),
                  ],
              ],
            );
          },
        );
      },
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({
    required this.entry,
    required this.spec,
    required this.canDelete,
    required this.onDelete,
  });

  final LogbookEntry entry;
  final _ModuleSpec spec;
  final bool canDelete;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final color = spec.color;
    final date = DateFormat(
      'd MMM yyyy, HH:mm',
      'id_ID',
    ).format(entry.activityDate);
    final quantity = entry.quantity > 0 && entry.unit.trim().isNotEmpty
        ? '${_number(entry.quantity)} ${entry.unit}'
        : null;
    final details = _detailItems(entry.details, spec);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.edit_note_outlined, color: color, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    entry.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (canDelete)
                  IconButton(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline),
                    color: AppColors.error,
                    tooltip: 'Hapus riwayat',
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _HistoryBadge(
                  icon: Icons.calendar_today_outlined,
                  label: date,
                  color: AppColors.textMuted,
                ),
                _HistoryBadge(
                  icon: Icons.check_circle_outline,
                  label: entry.status.isEmpty ? 'completed' : entry.status,
                  color: AppColors.success,
                ),
                if (quantity != null)
                  _HistoryBadge(
                    icon: Icons.straighten_outlined,
                    label: quantity,
                    color: color,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              entry.activityType,
              style: const TextStyle(
                color: AppColors.textMedium,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (entry.note.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                entry.note,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.textMuted),
              ),
            ],
            if (details.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final item in details)
                    _DetailPill(label: item.label, value: item.value),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HistoryBadge extends StatelessWidget {
  const _HistoryBadge({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailPill extends StatelessWidget {
  const _DetailPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 220),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.field,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textDark,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailItem {
  const _DetailItem({required this.label, required this.value});

  final String label;
  final String value;
}

class _BannerStat {
  const _BannerStat(this.label, this.value);

  final String label;
  final String value;
}

class _ModuleBanner extends StatelessWidget {
  const _ModuleBanner({
    required this.label,
    required this.desc,
    required this.icon,
    required this.color,
    required this.stats,
  });

  final String label;
  final String desc;
  final IconData icon;
  final Color color;
  final List<_BannerStat> stats;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color, color.withValues(alpha: 0.7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            desc,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Row(
            children: stats
                .map(
                  (s) => Expanded(
                    child: Column(
                      children: [
                        Text(
                          s.value,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        Text(
                          s.label,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _ModuleSpec {
  const _ModuleSpec({
    required this.label,
    required this.moduleType,
    required this.title,
    required this.activityType,
    required this.bannerLabel,
    required this.icon,
    required this.color,
    required this.sections,
    required this.notesKey,
    this.quantityKey,
    this.quantityUnit,
    this.slider,
  });

  final String label;
  final String moduleType;
  final String title;
  final String activityType;
  final String bannerLabel;
  final IconData icon;
  final Color color;
  final List<_FieldSection> sections;
  final String notesKey;
  final String? quantityKey;
  final String? quantityUnit;
  final _SliderSpec? slider;
}

class _FieldSection {
  const _FieldSection({
    required this.title,
    required this.icon,
    required this.color,
    required this.fields,
  });

  final String title;
  final IconData icon;
  final Color color;
  final List<_FieldSpec> fields;
}

class _FieldSpec {
  const _FieldSpec({
    required this.key,
    required this.label,
    required this.hint,
    this.type = TextInputType.text,
    this.suffix,
    this.maxLines = 1,
  });

  final String key;
  final String label;
  final String hint;
  final TextInputType type;
  final String? suffix;
  final int maxLines;
}

class _SliderSpec {
  const _SliderSpec({
    required this.key,
    required this.label,
    required this.unit,
    required this.min,
    required this.max,
    required this.color,
  });

  final String key;
  final String label;
  final String unit;
  final double min;
  final double max;
  final Color color;
}

const _ayamSpec = _ModuleSpec(
  label: 'Modul Ayam',
  moduleType: 'ayam_kampung',
  title: 'Catatan Harian Modul Ayam',
  activityType: 'input_harian_ayam',
  bannerLabel: 'Modul Ayam',
  icon: Icons.egg_alt_outlined,
  color: AppColors.warning,
  quantityKey: 'produksi_telur_hari_ini',
  quantityUnit: 'butir',
  notesKey: 'catatan_kejadian_khusus',
  slider: _SliderSpec(
    key: 'mortalitas_hari_ini',
    label: 'Mortalitas Hari Ini',
    unit: 'ekor',
    min: 0,
    max: 10,
    color: AppColors.error,
  ),
  sections: [
    _FieldSection(
      title: 'Input Harian',
      icon: Icons.edit_outlined,
      color: AppColors.warning,
      fields: [
        _FieldSpec(
          key: 'populasi_aktif',
          label: 'Populasi Aktif',
          hint: 'Jumlah ekor',
          type: TextInputType.number,
          suffix: 'ekor',
        ),
        _FieldSpec(
          key: 'konsumsi_pakan_g_per_ekor',
          label: 'Konsumsi Pakan',
          hint: 'Gram per ekor per hari',
          type: TextInputType.number,
          suffix: 'g/ekor',
        ),
        _FieldSpec(
          key: 'produksi_telur_hari_ini',
          label: 'Produksi Telur Hari Ini',
          hint: 'Jumlah butir',
          type: TextInputType.number,
          suffix: 'butir',
        ),
        _FieldSpec(
          key: 'berat_rata_rata_telur',
          label: 'Berat Rata-rata Telur',
          hint: 'Gram per butir',
          type: TextInputType.number,
          suffix: 'gram',
        ),
        _FieldSpec(
          key: 'catatan_kejadian_khusus',
          label: 'Catatan Kejadian Khusus',
          hint: 'Contoh: ayam terlihat lesu, perlu vaksin...',
          maxLines: 3,
        ),
      ],
    ),
    _FieldSection(
      title: 'Rincian Pakan & Nutrisi',
      icon: Icons.restaurant_outlined,
      color: AppColors.accentBrown,
      fields: [
        _FieldSpec(
          key: 'dedak_padi_kg',
          label: 'Dedak Padi',
          hint: 'kg',
          type: TextInputType.number,
          suffix: 'kg',
        ),
        _FieldSpec(
          key: 'talas_pepaya_kg',
          label: 'Talas & Pepaya',
          hint: 'kg',
          type: TextInputType.number,
          suffix: 'kg',
        ),
        _FieldSpec(
          key: 'maggot_segar_kg',
          label: 'Maggot Segar (suplemen)',
          hint: 'kg',
          type: TextInputType.number,
          suffix: 'kg',
        ),
        _FieldSpec(
          key: 'total_biaya_pakan',
          label: 'Total Biaya Pakan',
          hint: 'Rp',
          type: TextInputType.number,
          suffix: 'Rp',
        ),
      ],
    ),
    _FieldSection(
      title: 'Catatan Kesehatan',
      icon: Icons.health_and_safety_outlined,
      color: AppColors.info,
      fields: [
        _FieldSpec(
          key: 'kondisi_kandang',
          label: 'Kondisi Kandang',
          hint: '1-10',
          type: TextInputType.number,
        ),
        _FieldSpec(
          key: 'suhu_kandang',
          label: 'Suhu Kandang',
          hint: 'C',
          type: TextInputType.number,
          suffix: 'C',
        ),
        _FieldSpec(
          key: 'gejala_penyakit',
          label: 'Gejala / Penyakit Terdeteksi',
          hint: 'Kosongkan jika tidak ada kejadian',
          maxLines: 2,
        ),
      ],
    ),
  ],
);

const _maggotSpec = _ModuleSpec(
  label: 'Modul Maggot',
  moduleType: 'maggot_bsf',
  title: 'Catatan Harian Modul Maggot',
  activityType: 'input_harian_maggot',
  bannerLabel: 'Modul Maggot BSF',
  icon: Icons.bug_report_outlined,
  color: AppColors.accentLightGreen,
  quantityKey: 'volume_limbah_masuk_kg',
  quantityUnit: 'kg',
  notesKey: 'catatan_perawatan',
  slider: _SliderSpec(
    key: 'fase_larva_hari',
    label: 'Fase Larva - Hari ke-',
    unit: '/14',
    min: 1,
    max: 14,
    color: AppColors.accentLightGreen,
  ),
  sections: [
    _FieldSection(
      title: 'Input Limbah Organik',
      icon: Icons.recycling_outlined,
      color: AppColors.accentBrown,
      fields: [
        _FieldSpec(
          key: 'volume_limbah_masuk_kg',
          label: 'Volume Limbah Masuk',
          hint: 'kg',
          type: TextInputType.number,
          suffix: 'kg',
        ),
        _FieldSpec(
          key: 'jenis_limbah_utama',
          label: 'Jenis Limbah Utama',
          hint: 'sisa nasi, sayur, dll.',
        ),
        _FieldSpec(
          key: 'kadar_air_limbah_persen',
          label: 'Kadar Air Limbah',
          hint: '% estimasi',
          type: TextInputType.number,
          suffix: '%',
        ),
        _FieldSpec(
          key: 'asal_limbah',
          label: 'Asal Limbah',
          hint: 'RT / warung / pasar',
        ),
      ],
    ),
    _FieldSection(
      title: 'Status Larva & Fase Pertumbuhan',
      icon: Icons.timeline_outlined,
      color: AppColors.accentLightGreen,
      fields: [
        _FieldSpec(
          key: 'suhu_media',
          label: 'Suhu Media',
          hint: 'C',
          type: TextInputType.number,
          suffix: 'C',
        ),
        _FieldSpec(
          key: 'kelembapan_media',
          label: 'Jumlah Rak Aktif',
          hint: 'unit',
          type: TextInputType.number,
          suffix: 'rak',
        ),
      ],
    ),
    _FieldSection(
      title: 'Estimasi & Rencana Panen',
      icon: Icons.agriculture_outlined,
      color: AppColors.primaryGreen,
      fields: [
        _FieldSpec(
          key: 'estimasi_panen_kg',
          label: 'Estimasi Panen Larva',
          hint: 'kg',
          type: TextInputType.number,
          suffix: 'kg',
        ),
        _FieldSpec(
          key: 'target_panen_larva_kg',
          label: 'Target Panen Larva',
          hint: 'kg',
          type: TextInputType.number,
          suffix: 'kg',
        ),
        _FieldSpec(
          key: 'panen_prepupa_kering_kg',
          label: 'Panen Prepupa (kering)',
          hint: 'kg',
          type: TextInputType.number,
          suffix: 'kg',
        ),
        _FieldSpec(
          key: 'alokasi_larva_lele_persen',
          label: 'Alokasi Larva (lele/ayam)',
          hint: '%',
          type: TextInputType.number,
          suffix: '% lele',
        ),
        _FieldSpec(
          key: 'kondisi_media',
          label: 'Kondisi Media',
          hint: 'kering, basah, stabil...',
        ),
        _FieldSpec(
          key: 'catatan_perawatan',
          label: 'Catatan Batch Ini',
          hint: 'kualitas, anomali, suhu, dll.',
          maxLines: 3,
        ),
      ],
    ),
  ],
);

const _cacingSpec = _ModuleSpec(
  label: 'Modul Cacing',
  moduleType: 'cacing_tanah',
  title: 'Catatan Harian Modul Cacing',
  activityType: 'input_harian_cacing',
  bannerLabel: 'Modul Cacing Tanah (ANC)',
  icon: Icons.grass_outlined,
  color: AppColors.primaryGreenDark,
  quantityKey: 'pakan_organik_kg',
  quantityUnit: 'kg',
  notesKey: 'catatan_perawatan',
  sections: [
    _FieldSection(
      title: 'Input Harian - Cacing',
      icon: Icons.edit_outlined,
      color: AppColors.primaryGreenDark,
      fields: [
        _FieldSpec(
          key: 'media_cacing_kg',
          label: 'Jumlah Bibit',
          hint: 'kg',
          type: TextInputType.number,
          suffix: 'kg',
        ),
        _FieldSpec(
          key: 'kelembapan_media_persen',
          label: 'Kelembaban Media',
          hint: '%',
          type: TextInputType.number,
          suffix: '%',
        ),
        _FieldSpec(
          key: 'pakan_organik_kg',
          label: 'Pakan Diberikan',
          hint: 'kg',
          type: TextInputType.number,
          suffix: 'kg',
        ),
        _FieldSpec(
          key: 'kondisi_media',
          label: 'Jenis Pakan',
          hint: 'Limbah organik, kotoran...',
        ),
        _FieldSpec(
          key: 'panen_kascing_kg',
          label: 'Hasil Kascing (jika panen)',
          hint: 'kg',
          type: TextInputType.number,
          suffix: 'kg',
        ),
        _FieldSpec(
          key: 'suhu_media',
          label: 'Estimasi Panen Berikutnya',
          hint: 'hari ke-',
          type: TextInputType.number,
          suffix: 'hari lagi',
        ),
        _FieldSpec(
          key: 'kascing_cair_liter',
          label: 'Kascing Cair',
          hint: 'liter',
          type: TextInputType.number,
          suffix: 'L',
        ),
        _FieldSpec(
          key: 'catatan_perawatan',
          label: 'Catatan Kejadian',
          hint: 'kondisi media, suhu, dll.',
          maxLines: 2,
        ),
      ],
    ),
  ],
);

const _tanamanSpec = _ModuleSpec(
  label: 'Modul Tanaman',
  moduleType: 'tanaman',
  title: 'Catatan Harian Modul Tanaman',
  activityType: 'input_harian_tanaman',
  bannerLabel: 'Modul Tanaman Pangan Organik',
  icon: Icons.eco_outlined,
  color: AppColors.success,
  quantityKey: 'pupuk_kascing_cair_liter',
  quantityUnit: 'L/m2',
  notesKey: 'catatan_kondisi_tanaman',
  sections: [
    _FieldSection(
      title: 'Data Tanam & Pertumbuhan',
      icon: Icons.edit_outlined,
      color: AppColors.success,
      fields: [
        _FieldSpec(
          key: 'jenis_tanaman',
          label: 'Jenis Tanaman',
          hint: 'Talas, singkong, dll.',
        ),
        _FieldSpec(
          key: 'blok_lokasi',
          label: 'Blok / Lokasi',
          hint: 'Blok A, B, C...',
        ),
        _FieldSpec(
          key: 'tanggal_tanam',
          label: 'Tanggal Tanam',
          hint: 'DD/MM/YYYY',
        ),
        _FieldSpec(
          key: 'usia_tanaman',
          label: 'Usia Tanaman',
          hint: 'hari',
          type: TextInputType.number,
          suffix: 'hari',
        ),
        _FieldSpec(
          key: 'tinggi_tanaman_cm',
          label: 'Tinggi Tanaman',
          hint: 'cm',
          type: TextInputType.number,
          suffix: 'cm',
        ),
        _FieldSpec(
          key: 'jumlah_daun',
          label: 'Jumlah Daun',
          hint: 'lembar',
          type: TextInputType.number,
          suffix: 'lbr',
        ),
        _FieldSpec(
          key: 'pupuk_kascing_cair_liter',
          label: 'Pupuk Kascing Cair',
          hint: 'L',
          type: TextInputType.number,
          suffix: 'L/m2',
        ),
        _FieldSpec(
          key: 'pupuk_kascing_kg',
          label: 'Pupuk Kascing Padat',
          hint: 'kg',
          type: TextInputType.number,
          suffix: 'kg',
        ),
        _FieldSpec(
          key: 'hasil_panen_kg',
          label: 'Hasil Panen',
          hint: 'kg',
          type: TextInputType.number,
          suffix: 'kg',
        ),
        _FieldSpec(
          key: 'jadwal_pemupukan_berikutnya',
          label: 'Jadwal Pemupukan Berikutnya',
          hint: 'DD/MM/YYYY',
        ),
        _FieldSpec(
          key: 'catatan_kondisi_tanaman',
          label: 'Catatan Kondisi Tanaman',
          hint: 'hama, pertumbuhan, dll.',
          maxLines: 2,
        ),
      ],
    ),
  ],
);

const _leleSpec = _ModuleSpec(
  label: 'Modul Lele',
  moduleType: 'lele',
  title: 'Catatan Harian Modul Lele',
  activityType: 'input_harian_lele',
  bannerLabel: 'Modul Lele Organik',
  icon: Icons.water_drop_outlined,
  color: AppColors.info,
  quantityKey: 'pakan_lele_kg',
  quantityUnit: 'kg',
  notesKey: 'catatan_kolam',
  sections: [
    _FieldSection(
      title: 'Input Harian - Lele',
      icon: Icons.edit_outlined,
      color: AppColors.info,
      fields: [
        _FieldSpec(
          key: 'jumlah_ikan',
          label: 'Jumlah Tebar Benih',
          hint: 'ekor',
          type: TextInputType.number,
          suffix: 'ekor',
        ),
        _FieldSpec(
          key: 'kondisi_air',
          label: 'Survival Rate Saat Ini',
          hint: '%',
          type: TextInputType.number,
          suffix: '%',
        ),
        _FieldSpec(
          key: 'pakan_maggot_pagi_kg',
          label: 'Pakan Maggot Pagi',
          hint: 'kg',
          type: TextInputType.number,
          suffix: 'kg',
        ),
        _FieldSpec(
          key: 'pakan_lele_kg',
          label: 'Pakan Maggot Sore',
          hint: 'kg',
          type: TextInputType.number,
          suffix: 'kg',
        ),
        _FieldSpec(
          key: 'ph_air',
          label: 'pH Air Kolam',
          hint: '6.5-8.0 ideal',
          type: TextInputType.numberWithOptions(decimal: true),
          suffix: 'pH',
        ),
        _FieldSpec(
          key: 'suhu_air',
          label: 'Suhu Air',
          hint: 'C',
          type: TextInputType.number,
          suffix: 'C',
        ),
        _FieldSpec(
          key: 'mortalitas_ikan',
          label: 'Bobot Rata-rata',
          hint: 'gram/ekor',
          type: TextInputType.number,
          suffix: 'g',
        ),
        _FieldSpec(
          key: 'estimasi_panen_hari',
          label: 'Estimasi Panen',
          hint: 'hari lagi',
          type: TextInputType.number,
          suffix: 'hari',
        ),
        _FieldSpec(
          key: 'panen_lele_kg',
          label: 'Panen Lele',
          hint: 'kg',
          type: TextInputType.number,
          suffix: 'kg',
        ),
        _FieldSpec(
          key: 'catatan_kolam',
          label: 'Catatan Kolam',
          hint: 'kualitas air, kematian, dll.',
          maxLines: 2,
        ),
      ],
    ),
  ],
);

String _number(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toString();

List<_DetailItem> _detailItems(Map<String, dynamic> details, _ModuleSpec spec) {
  if (details.isEmpty) return const [];
  final labels = <String, String>{
    if (spec.slider != null) spec.slider!.key: spec.slider!.label,
    for (final section in spec.sections)
      for (final field in section.fields) field.key: field.label,
  };

  final items = <_DetailItem>[];
  for (final entry in details.entries) {
    final value = _displayDetailValue(entry.value);
    if (value.isEmpty) continue;
    items.add(
      _DetailItem(
        label: labels[entry.key] ?? _fallbackDetailLabel(entry.key),
        value: value,
      ),
    );
  }
  return items;
}

String _displayDetailValue(Object? value) {
  if (value == null) return '';
  if (value is num) return _number(value.toDouble());
  if (value is bool) return value ? 'Ya' : 'Tidak';
  final text = value.toString().trim();
  return text;
}

String _fallbackDetailLabel(String key) {
  final words = key
      .split('_')
      .where((part) => part.trim().isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}');
  return words.join(' ');
}

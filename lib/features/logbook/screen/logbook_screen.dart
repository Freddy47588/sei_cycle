import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../inventory/services/inventory_service.dart';
import '../../profile/models/app_user.dart';
import 'package:uuid/uuid.dart';
import '../models/logbook_form_spec.dart';
import 'logbook_list_screen.dart';
import 'logbook_detail_screen.dart';
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
        label: const Text('Daftar Logbook'),
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
  LogbookModuleSpec get spec => ayamSpec;

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
  LogbookModuleSpec get spec => maggotSpec;

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
  LogbookModuleSpec get spec => cacingSpec;

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
  LogbookModuleSpec get spec => tanamanSpec;

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
  LogbookModuleSpec get spec => leleSpec;

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
  bool _saved = false;
  String _requestId = const Uuid().v4();
  double? _sliderValue;

  LogbookModuleSpec get spec;
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
    if (!canSave || _saving || _saved) return;
    if (_values.values.every((value) => value.trim().isEmpty)) {
      _showMessage('Isi hasil pengamatan sebelum menyimpan catatan.');
      return;
    }
    if (userId.trim().isEmpty) {
      _showMessage('User belum terdeteksi. Silakan login ulang.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    try {
      final details = <String, dynamic>{};
      for (final entry in _values.entries) {
        details[entry.key] = _typedValue(entry.key, entry.value);
      }
      validateLogbookDetails(spec.moduleType, details);
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
      final savedId = await _service.createDailyEntry(
        requestId: _requestId,
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
      _saved = true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Catatan ${spec.label} berhasil disimpan.'),
          action: SnackBarAction(
            label: 'Lihat Catatan',
            onPressed: () => _openDetail(savedId),
          ),
        ),
      );
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
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LogbookListScreen(
          service: _service,
          initialModuleId: spec.moduleType,
          userId: userId,
          canEdit: canSave,
        ),
      ),
    );
  }

  void _openDetail(String id) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LogbookDetailScreen(
          service: _service,
          entryId: id,
          userId: userId,
          canEdit: canSave,
        ),
      ),
    );
  }

  void _changeValue(String key, String value) {
    if (_values[key] == value) return;
    _values[key] = value;
    _saved = false;
    _requestId = const Uuid().v4();
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

  Object? _typedValue(String key, String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';
    final numeric =
        spec.slider?.key == key ||
        spec.sections.any(
          (section) => section.fields.any(
            (field) =>
                field.key == key &&
                field.type.index == TextInputType.number.index,
          ),
        );
    return numeric
        ? double.tryParse(trimmed.replaceAll(',', '.')) ?? trimmed
        : trimmed;
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
    return AbsorbPointer(
      absorbing: _saving,
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(
          children: [
            _ModuleBanner(
              label: spec.bannerLabel,
              desc:
                  'Catat hasil pengamatan aktual ${spec.label.toLowerCase()}.',
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
                                        () => _changeValue(field.key, value),
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
                                setState(() {
                                  _sliderValue = value;
                                  _changeValue(
                                    spec.slider!.key,
                                    value.toStringAsFixed(0),
                                  );
                                });
                              },
                            ),
                          if (section == spec.sections.first &&
                              spec.moduleType == 'maggot_bsf' &&
                              _sliderValue != null)
                            _PhaseBadge(hari: (_sliderValue ?? 12).toInt()),
                        ],
                      ),
                    if (_saved)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: Text(
                          'Catatan sudah tersimpan. Ubah isian untuk membuat catatan baru.',
                        ),
                      ),
                    _buildSubmitRow(
                      onHistory: _openHistory,
                      onSubmit: canSave && !_saved ? _submit : null,
                      saving: _saving,
                    ),
                  ],
                );
              },
            ),
          ],
        ),
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

  final LogbookSliderSpec spec;
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

String _number(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toString();

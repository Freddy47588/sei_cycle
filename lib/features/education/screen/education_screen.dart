import 'package:flutter/material.dart';

import '../../../core/constants/farm_modules.dart';
import '../../../core/utils/delete_confirmation.dart';
import '../../../core/utils/operation_feedback.dart';
import '../../../core/widgets/app_ui.dart';
import '../../../core/widgets/async_state_widgets.dart';
import '../../../core/widgets/feature_page.dart';
import '../../../theme/app_theme.dart';
import '../../profile/models/app_user.dart';
import '../models/education_content.dart';
import '../services/education_service.dart';

class EducationScreen extends StatefulWidget {
  const EducationScreen({required this.profile, this.contents, super.key});
  final Stream<List<EducationContent>>? contents;

  final AppUser profile;

  @override
  State<EducationScreen> createState() => _EducationScreenState();
}

class _EducationScreenState extends State<EducationScreen> {
  late final EducationService _service = EducationService();
  String _query = '';
  String? _type;
  String? _moduleType;

  @override
  void initState() {
    super.initState();
  }

  Future<void> _openForm([EducationContent? content]) async {
    final value = await showDialog<_EducationFormValue>(
      context: context,
      builder: (_) => _EducationFormDialog(content: content),
    );
    if (value == null || !mounted) return;
    await runOperationWithFeedback(
      context,
      operation: () => _service.save(
        id: content?.id,
        title: value.title,
        type: value.type,
        content: value.content,
        externalUrl: value.externalUrl,
        status: value.status,
        moduleType: value.moduleType,
        userId: widget.profile.uid,
      ),
      successMessage: content == null
          ? 'Konten ditambahkan.'
          : 'Konten diperbarui.',
    );
  }

  Future<void> _delete(EducationContent content) async {
    final confirmed = await confirmDelete(
      context,
      title: 'Hapus konten?',
      message: 'Konten ${content.title} akan dihapus dari materi edukasi.',
    );
    if (!confirmed || !mounted) return;
    await runOperationWithFeedback(
      context,
      operation: () => _service.delete(content.id, userId: widget.profile.uid),
      successMessage: 'Konten dihapus.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, pageConstraints) => FeaturePage(
        title: 'Edukasi Kebun Sei',
        subtitle: 'Artikel, tutorial, dan SOP praktis untuk tim kebun',
        actions: [
          if (widget.profile.canManageEducation)
            FilledButton.icon(
              onPressed: _openForm,
              icon: const Icon(Icons.add),
              label: const Text('Tambah konten'),
            ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              onChanged: (value) => setState(() => _query = value),
              decoration: const InputDecoration(
                hintText: 'Cari artikel atau tutorial...',
                prefixIcon: Icon(Icons.search, color: AppColors.primaryGreen),
                fillColor: AppColors.surface,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: AppFilterChip(
                      selected: _type == null && _moduleType == null,
                      label: 'Semua',
                      icon: Icons.school_outlined,
                      color: AppColors.primaryGreen,
                      onSelected: () => setState(() {
                        _type = null;
                        _moduleType = null;
                      }),
                    ),
                  ),
                  for (final module in FarmModules.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: AppFilterChip(
                        selected: _moduleType == module.id,
                        label: module.name,
                        icon: _moduleIcon(module.id),
                        color: _moduleColor(module.id),
                        onSelected: () =>
                            setState(() => _moduleType = module.id),
                      ),
                    ),
                  for (final type in EducationType.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: AppFilterChip(
                        selected: _type == type,
                        label: _educationTypeLabel(type),
                        icon: _iconForType(type),
                        color: _colorForType(type),
                        onSelected: () => setState(() => _type = type),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: StreamBuilder<List<EducationContent>>(
                stream:
                    widget.contents ??
                    _service.watchContents(
                      includeDrafts: widget.profile.canManageEducation,
                      type: _type,
                      moduleType: _moduleType,
                    ),
                builder: (context, snapshot) {
                  final state = asyncSnapshotState(snapshot);
                  if (state != null) return state;
                  final query = _query.trim().toLowerCase();
                  final contents = snapshot.requireData.where((item) {
                    final matchesQuery =
                        query.isEmpty ||
                        item.title.toLowerCase().contains(query) ||
                        item.previewText.toLowerCase().contains(query);
                    return matchesQuery;
                  }).toList();
                  if (contents.isEmpty) {
                    return EmptyState(
                      title:
                          _query.isEmpty && _type == null && _moduleType == null
                          ? 'Belum ada materi edukasi'
                          : 'Materi tidak ditemukan',
                      message: _query.isEmpty
                          ? 'Panduan akan muncul setelah admin menerbitkan konten pertama.'
                          : 'Coba gunakan kata kunci lain atau ubah filter pencarian.',
                      icon: Icons.school_outlined,
                    );
                  }
                  return LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = constraints.maxWidth >= 900
                          ? 3
                          : pageConstraints.maxWidth >=
                                AppBreakpoints.formColumns
                          ? 2
                          : 1;
                      return GridView.builder(
                        padding: const EdgeInsets.only(bottom: 12),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          crossAxisSpacing: 20,
                          mainAxisSpacing: 20,
                          mainAxisExtent:
                              360 +
                              (MediaQuery.textScalerOf(context).scale(1) - 1) *
                                  160,
                        ),
                        itemCount: contents.length,
                        itemBuilder: (context, index) {
                          return _EducationCard(
                            content: contents[index],
                            canEdit: widget.profile.canManageEducation,
                            canDelete: widget.profile.canDeleteEducation,
                            onEdit: () => _openForm(contents[index]),
                            onDelete: () => _delete(contents[index]),
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EducationCard extends StatelessWidget {
  const _EducationCard({
    required this.content,
    required this.canEdit,
    required this.canDelete,
    required this.onEdit,
    required this.onDelete,
  });

  final EducationContent content;
  final bool canEdit;
  final bool canDelete;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final color = _colorForType(content.type);
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 150,
            width: double.infinity,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _EducationImage(content: content),
                if (content.type == EducationType.video)
                  const Center(
                    child: CircleAvatar(
                      backgroundColor: Colors.black45,
                      foregroundColor: Colors.white,
                      radius: 22,
                      child: Icon(Icons.play_arrow_rounded, size: 32),
                    ),
                  ),
                Positioned(
                  right: 12,
                  top: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Text(
                      _educationTypeLabel(content.type),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _educationCategory(content),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _moduleColor(content.moduleType),
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    content.displayTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: Text(
                      content.previewText,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Icon(
                        _iconForType(content.type),
                        size: 17,
                        color: AppColors.textMuted,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          content.type == EducationType.video
                              ? 'Video Tutorial'
                              : _educationTypeLabel(content.type),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(color: AppColors.textMuted),
                        ),
                      ),
                      if (canEdit || canDelete)
                        PopupMenuButton<String>(
                          tooltip: 'Opsi konten',
                          icon: const Icon(Icons.more_vert_rounded, size: 20),
                          onSelected: (value) {
                            if (value == 'edit') onEdit();
                            if (value == 'delete') onDelete();
                          },
                          itemBuilder: (_) => [
                            if (canEdit)
                              const PopupMenuItem(
                                value: 'edit',
                                child: Text('Edit konten'),
                              ),
                            if (canDelete)
                              const PopupMenuItem(
                                value: 'delete',
                                child: Text('Hapus konten'),
                              ),
                          ],
                        )
                      else
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: AppColors.primaryGreen,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EducationImage extends StatelessWidget {
  const _EducationImage({required this.content});

  final EducationContent content;

  @override
  Widget build(BuildContext context) {
    final fallback = _educationAsset(content);
    if (content.thumbnailUrl.isNotEmpty) {
      return Image.network(
        content.thumbnailUrl,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, progress) => progress == null
            ? child
            : const ColoredBox(
                color: AppColors.surfaceVariant,
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
        errorBuilder: (_, _, _) => Image.asset(
          fallback,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const Icon(
            Icons.image_not_supported_outlined,
            color: AppColors.textMuted,
          ),
        ),
      );
    }
    return Image.asset(fallback, fit: BoxFit.cover);
  }
}

String _educationAsset(EducationContent content) {
  if (content.type == EducationType.video && content.moduleType == 'lele') {
    return 'lib/assets/edukasi/lele_bioflok.png';
  }
  return switch (content.moduleType) {
    'ayam_kampung' => 'lib/assets/edukasi/ayam_pakan.png',
    'maggot_bsf' => 'lib/assets/edukasi/maggot_bsf.png',
    'cacing_tanah' =>
      content.type == EducationType.video
          ? 'lib/assets/edukasi/panen_kascing.png'
          : 'lib/assets/edukasi/cacing_media.png',
    'lele' => 'lib/assets/edukasi/lele_fcr.png',
    'tanaman' => 'lib/assets/edukasi/tanaman_kangkung.png',
    _ => 'lib/assets/edukasi/siklus_nutrisi.png',
  };
}

String _educationCategory(EducationContent content) {
  if (content.moduleType.isNotEmpty) {
    return FarmModules.nameOf(content.moduleType).toUpperCase();
  }
  return EducationType.label(content.type).toUpperCase();
}

String _educationTypeLabel(String type) => switch (type) {
  EducationType.video => 'Video Tutorial',
  EducationType.sop => 'SOP',
  _ => 'Artikel',
};

Color _moduleColor(String moduleType) => switch (moduleType) {
  'ayam_kampung' => AppColors.warning,
  'maggot_bsf' => AppColors.accentBrown,
  'cacing_tanah' => AppColors.primaryGreen,
  'lele' => AppColors.info,
  'tanaman' => AppColors.success,
  _ => AppColors.primaryGreen,
};

IconData _moduleIcon(String moduleType) => switch (moduleType) {
  'ayam_kampung' => Icons.egg_alt_outlined,
  'maggot_bsf' => Icons.pest_control_outlined,
  'cacing_tanah' => Icons.grass_outlined,
  'lele' => Icons.water_drop_outlined,
  'tanaman' => Icons.eco_outlined,
  _ => Icons.category_outlined,
};

IconData _iconForType(String type) => switch (type) {
  EducationType.video => Icons.ondemand_video_outlined,
  EducationType.sop => Icons.fact_check_outlined,
  _ => Icons.article_outlined,
};

Color _colorForType(String type) => switch (type) {
  EducationType.video => AppColors.info,
  EducationType.sop => AppColors.accentBrown,
  _ => AppColors.primaryGreen,
};

class _EducationFormValue {
  const _EducationFormValue({
    required this.title,
    required this.type,
    required this.content,
    required this.externalUrl,
    required this.status,
    required this.moduleType,
  });

  final String title;
  final String type;
  final String content;
  final String externalUrl;
  final String status;
  final String moduleType;
}

class _EducationFormDialog extends StatefulWidget {
  const _EducationFormDialog({this.content});

  final EducationContent? content;

  @override
  State<_EducationFormDialog> createState() => _EducationFormDialogState();
}

class _EducationFormDialogState extends State<_EducationFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _content;
  late final TextEditingController _url;
  late String _type;
  late String _status;
  String? _moduleType;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.content?.title);

    // Reverse logic for content based on type for the simple form
    String initialContent = widget.content?.content ?? '';
    if (widget.content?.type == EducationType.sop &&
        widget.content!.steps.isNotEmpty) {
      initialContent = widget.content!.steps.join('\n');
    }
    _content = TextEditingController(text: initialContent);
    _url = TextEditingController(text: widget.content?.videoUrl);
    _type = widget.content?.type ?? EducationType.article;
    _status = widget.content?.status ?? EducationStatus.draft;
    _moduleType = (widget.content?.moduleType.isNotEmpty ?? false)
        ? widget.content!.moduleType
        : null;
  }

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    _url.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      _EducationFormValue(
        title: _title.text,
        type: _type,
        content: _content.text,
        externalUrl: _url.text,
        status: _status,
        moduleType: _moduleType ?? '',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppDialogShell(
      title: widget.content == null ? 'Tambah Edukasi' : 'Edit Edukasi',
      maxWidth: 560,
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'Judul'),
              validator: _required,
            ),
            const SizedBox(height: 12),
            ResponsiveFormRow(
              breakpoint: 400,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _type,
                  decoration: const InputDecoration(labelText: 'Tipe'),
                  items: [
                    for (final type in EducationType.values)
                      DropdownMenuItem(
                        value: type,
                        child: Text(EducationType.label(type)),
                      ),
                  ],
                  onChanged: (value) => setState(() => _type = value!),
                ),
                DropdownButtonFormField<String?>(
                  initialValue: _moduleType,
                  decoration: const InputDecoration(
                    labelText: 'Modul (Opsional)',
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Umum')),
                    for (final module in FarmModules.values)
                      DropdownMenuItem(
                        value: module.id,
                        child: Text(module.name),
                      ),
                  ],
                  onChanged: (value) => setState(() => _moduleType = value),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _content,
              maxLines: 7,
              decoration: InputDecoration(
                labelText: _type == EducationType.sop
                    ? 'Langkah SOP (pisahkan dengan enter)'
                    : 'Isi konten/deskripsi',
              ),
              validator: _required,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _url,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'External URL (Opsional untuk video)',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _status,
              decoration: const InputDecoration(labelText: 'Status Publikasi'),
              items: [
                for (final status in EducationStatus.values)
                  DropdownMenuItem(
                    value: status,
                    child: Text(EducationStatus.label(status)),
                  ),
              ],
              onChanged: (value) => setState(() => _status = value!),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Simpan')),
      ],
    );
  }
}

String? _required(String? value) =>
    value == null || value.trim().isEmpty ? 'Wajib diisi' : null;

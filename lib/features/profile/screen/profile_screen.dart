import 'package:flutter/material.dart';

import '../../../core/services/local_reminder_service.dart';
import '../../../core/services/messaging_service.dart';
import '../../../core/widgets/app_ui.dart';
import '../../../core/widgets/feature_page.dart';
import '../../../theme/app_theme.dart';
import '../../auth/services/auth_service.dart';
import '../../farm_modules/services/farm_module_service.dart';
import '../models/app_user.dart';
import '../services/user_profile_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({required this.profile, super.key});

  final AppUser profile;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final TextEditingController _name;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.profile.name);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _run(
    Future<void> Function() action,
    String successMessage,
  ) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(successMessage)));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Belum berhasil: $error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FeaturePage(
      title: 'Profil',
      subtitle: 'Kelola data akun dan preferensi penggunaan SeiCycle.',
      child: ListView(
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 32,
                      backgroundColor: AppColors.softGreen,
                      foregroundColor: AppColors.primaryGreen,
                      backgroundImage: widget.profile.photoUrl.isEmpty
                          ? null
                          : NetworkImage(widget.profile.photoUrl),
                      child: widget.profile.photoUrl.isEmpty
                          ? const Icon(Icons.person_rounded, size: 32)
                          : null,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.profile.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            widget.profile.email,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: AppColors.textMuted),
                          ),
                          const SizedBox(height: 7),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              StatusBadge(
                                label: widget.profile.roleLabel,
                                color: AppColors.primaryGreen,
                                icon: Icons.badge_outlined,
                              ),
                              StatusBadge(
                                label: widget.profile.isActive
                                    ? 'Aktif'
                                    : 'Nonaktif',
                                color: widget.profile.isActive
                                    ? AppColors.success
                                    : AppColors.error,
                                icon: widget.profile.isActive
                                    ? Icons.verified_user_outlined
                                    : Icons.block_outlined,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Nama tampilan',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _run(
                          () => UserProfileService().updateName(
                            widget.profile.uid,
                            _name.text,
                          ),
                          'Profil diperbarui.',
                        ),
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Simpan perubahan'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (widget.profile.canManageFarmModules) ...[
            _SettingsCard(
              icon: Icons.eco_outlined,
              title: 'Modul operasional default',
              subtitle:
                  'Siapkan lima modul kebun agar pilihan pencatatan tetap konsisten.',
              action: FilledButton(
                onPressed: _busy
                    ? null
                    : () => _run(
                        FarmModuleService().seedDefaults,
                        'Lima modul kebun berhasil disiapkan.',
                      ),
                child: const Text('Siapkan modul'),
              ),
            ),
            const SizedBox(height: 14),
          ],
          _SettingsCard(
            icon: Icons.notifications_active_outlined,
            title: 'Notifikasi perangkat',
            subtitle:
                'Izinkan SeiCycle menyiapkan notifikasi untuk pengingat operasional.',
            action: OutlinedButton(
              onPressed: _busy
                  ? null
                  : () => _run(() async {
                      await LocalReminderService().requestPermission();
                      await MessagingService().requestPermissionAndSaveToken(
                        widget.profile.uid,
                      );
                    }, 'Permintaan izin notifikasi selesai.'),
              child: const Text('Aktifkan'),
            ),
          ),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => AuthService().signOut(),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.error,
              side: const BorderSide(color: Color(0xFFF3C8C8)),
            ),
            icon: const Icon(Icons.logout),
            label: const Text('Keluar dari akun'),
          ),
        ],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.action,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 460;
          final info = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppIconBox(icon: icon, color: AppColors.primaryGreen),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [info, const SizedBox(height: 14), action],
            );
          }
          return Row(
            children: [
              Expanded(child: info),
              const SizedBox(width: 16),
              action,
            ],
          );
        },
      ),
    );
  }
}

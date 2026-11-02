import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'app_ui.dart';

Widget? asyncSnapshotState<T>(
  AsyncSnapshot<T> snapshot, {
  String loadingLabel = 'Memuat data...',
  String Function(Object error)? errorMessage,
  bool allowNullData = false,
}) {
  if (snapshot.hasError) {
    final error = snapshot.error!;
    return ErrorState(message: errorMessage?.call(error) ?? '$error');
  }
  final nullWasEmitted =
      allowNullData && snapshot.connectionState == ConnectionState.active;
  if (!snapshot.hasData && !nullWasEmitted) {
    return LoadingState(label: loadingLabel);
  }
  return null;
}

class LoadingState extends StatelessWidget {
  const LoadingState({super.key, this.label = 'Memuat data...'});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AppCard(
        borderColor: Colors.transparent,
        color: AppColors.surface.withValues(alpha: 0.72),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(height: 12),
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class ErrorState extends StatelessWidget {
  const ErrorState({required this.message, super.key, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: AppCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AppIconBox(
                  icon: Icons.cloud_off_outlined,
                  color: AppColors.error,
                  size: 52,
                ),
                const SizedBox(height: 14),
                Text(
                  'Data belum dapat dimuat',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
                ),
                if (onRetry != null) ...[
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Coba lagi'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.title,
    super.key,
    this.message,
    this.icon = Icons.inbox_outlined,
    this.action,
  });

  final String title;
  final String? message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIconBox(icon: icon, color: AppColors.primaryGreen, size: 56),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (message != null) ...[
                const SizedBox(height: 6),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
                ),
              ],
              if (action != null) ...[const SizedBox(height: 16), action!],
            ],
          ),
        ),
      ),
    );
  }
}

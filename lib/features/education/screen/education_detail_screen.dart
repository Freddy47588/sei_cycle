import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/farm_modules.dart';
import '../../../core/utils/formatters.dart';
import '../models/education_content.dart';
import '../services/education_service.dart';

class EducationDetailScreen extends StatelessWidget {
  const EducationDetailScreen({required this.content, super.key});
  final EducationContent content;
  Future<void> _openVideo(BuildContext context) async {
    try {
      if (!isSafeEducationUrl(content.videoUrl) ||
          !await launchUrl(
            Uri.parse(content.videoUrl),
            mode: LaunchMode.externalApplication,
          )) {
        throw StateError('Tautan video tidak dapat dibuka.');
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Tautan video tidak dapat dibuka. Periksa URL dan aplikasi browser.',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Materi edukasi')),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                content.displayTitle,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  Text(EducationType.label(content.type)),
                  Text(
                    content.moduleType.isEmpty
                        ? 'Umum'
                        : FarmModules.nameOf(content.moduleType),
                  ),
                  Text(EducationStatus.label(content.status)),
                  Text(shortDateFormat.format(content.updatedAt)),
                ],
              ),
              const Divider(height: 32),
              if (content.type == EducationType.sop) ...[
                if (content.toolsNeeded.isNotEmpty)
                  Text('Alat dan bahan: ${content.toolsNeeded.join(', ')}'),
                for (var i = 0; i < content.steps.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: SelectableText(
                      '${i + 1}. ${content.steps[i]}',
                      style: const TextStyle(height: 1.6),
                    ),
                  ),
                if (content.safetyNotes.isNotEmpty)
                  SelectableText('Keselamatan: ${content.safetyNotes}'),
              ] else
                SelectableText(
                  content.content,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.copyWith(height: 1.7),
                ),
              if (content.type == EducationType.video) ...[
                const SizedBox(height: 20),
                if (isSafeEducationUrl(content.videoUrl))
                  FilledButton.icon(
                    onPressed: () => _openVideo(context),
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Buka video di browser'),
                  )
                else
                  const Text('Tautan video belum tersedia atau tidak aman.'),
              ],
              if (content.tags.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: Text(content.tags.join(' · ')),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

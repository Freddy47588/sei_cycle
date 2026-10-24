import 'package:flutter/material.dart';
import '../../logbook/services/logbook_service.dart';
import '../models/cultivation_batch.dart';
import '../screen/batch_list_screen.dart';

class OperationalBatchPicker extends StatelessWidget {
  const OperationalBatchPicker({
    required this.moduleId,
    required this.batchId,
    required this.userId,
    required this.onChanged,
    this.service,
    super.key,
  });
  final String moduleId, userId;
  final String? batchId;
  final ValueChanged<String?>? onChanged;
  final LogbookService? service;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        batchId == null ? 'Tanpa Batch — Aktivitas Umum' : 'Batch: $batchId',
      ),
      Wrap(
        spacing: 8,
        children: [
          OutlinedButton(
            onPressed: onChanged == null || moduleId.isEmpty
                ? null
                : () async {
                    final logs = service ?? LogbookService();
                    final selected = await Navigator.push<CultivationBatch>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => BatchListScreen(
                          service: logs.batches,
                          logbookService: logs,
                          userId: userId,
                          canManage: true,
                          initialModule: moduleId,
                          selectActive: true,
                        ),
                      ),
                    );
                    if (selected != null) onChanged?.call(selected.id);
                  },
            child: const Text('Pilih batch aktif'),
          ),
          if (batchId != null)
            TextButton(
              onPressed: onChanged == null ? null : () => onChanged!(null),
              child: const Text('Tanpa Batch — Aktivitas Umum'),
            ),
        ],
      ),
    ],
  );
}

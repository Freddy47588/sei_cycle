import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/farm_modules.dart';
import '../../logbook/models/logbook_form_spec.dart';
import '../models/cultivation_batch.dart';

String batchDate(DateTime? value) => value == null
    ? 'Belum tersedia'
    : DateFormat('dd MMM yyyy', 'id_ID').format(value.toLocal());

class BatchCard extends StatelessWidget {
  const BatchCard({
    required this.batch,
    required this.onTap,
    this.selecting = false,
    super.key,
  });
  final CultivationBatch batch;
  final VoidCallback onTap;
  final bool selecting;
  @override
  Widget build(BuildContext context) {
    final spec = moduleSpecFor(batch.input.moduleType);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Icon(spec.icon, color: spec.color),
                Text(FarmModules.nameOf(batch.input.moduleType)),
                Chip(label: Text(batchStatusLabel(batch.status))),
              ],
            ),
            Text(
              batch.input.name,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text('Kode: ${batch.input.code}'),
            Text('Lokasi: ${batch.input.locationName}'),
            Text('Mulai: ${batchDate(batch.input.startedAt)}'),
            if (batch.input.expectedHarvestAt != null)
              Text(
                'Estimasi panen: ${batchDate(batch.input.expectedHarvestAt)}',
              ),
            TextButton(
              onPressed: onTap,
              child: Text(selecting ? 'Pilih Batch' : 'Lihat Detail'),
            ),
          ],
        ),
      ),
    );
  }
}

import '../../../core/utils/legacy_firestore.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/firestore_fields.dart';

class FarmModule {
  const FarmModule({
    required this.id,
    required this.name,
    required this.type,
    required this.description,
    required this.icon,
    required this.color,
    required this.isActive,
  });

  final String id;
  final String name;
  final String type;
  final String description;
  final String icon;
  final String color;
  final bool isActive;

  factory FarmModule.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const <String, dynamic>{};
    return FarmModule(
      id: canonicalModuleId(
        stringField(data, const [
          'id',
          'moduleType',
          'module_id',
        ], fallback: document.id),
      ),
      name: stringField(data, const [
        'name',
        'module_name',
      ], fallback: document.id),
      type: stringField(data, const [
        'type',
        'module_type',
      ], fallback: document.id),
      description: stringField(data, const ['description']),
      icon: stringField(data, const ['icon'], fallback: 'eco'),
      color: stringField(data, const ['color'], fallback: '#2D6A27'),
      isActive: boolField(data, const [
        'isActive',
        'is_active',
      ], fallback: true),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'description': description,
      'icon': icon,
      'color': color,
      'isActive': isActive,
    };
  }
}

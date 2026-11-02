class FarmModuleOption {
  const FarmModuleOption({
    required this.id,
    required this.name,
    required this.type,
    required this.description,
    required this.icon,
    required this.color,
  });

  final String id;
  final String name;
  final String type;
  final String description;
  final String icon;
  final String color;
}

abstract final class FarmModules {
  static const ayamKampung = FarmModuleOption(
    id: 'ayam_kampung',
    name: 'Ayam Kampung',
    type: 'ayam',
    description: 'Pencatatan pakan, produksi telur, dan kesehatan ayam.',
    icon: 'egg_alt',
    color: '#F59E0B',
  );
  static const maggotBsf = FarmModuleOption(
    id: 'maggot_bsf',
    name: 'Maggot BSF',
    type: 'maggot',
    description: 'Pencatatan limbah organik, fase larva, dan panen maggot.',
    icon: 'pest_control',
    color: '#8B6F47',
  );
  static const cacingTanah = FarmModuleOption(
    id: 'cacing_tanah',
    name: 'Cacing Tanah',
    type: 'cacing',
    description: 'Pencatatan media, kelembaban, pakan, dan kascing.',
    icon: 'grass',
    color: '#2D6A27',
  );
  static const lele = FarmModuleOption(
    id: 'lele',
    name: 'Lele',
    type: 'lele',
    description: 'Pencatatan pakan, kualitas air, pertumbuhan, dan panen.',
    icon: 'water_drop',
    color: '#3B82F6',
  );
  static const tanaman = FarmModuleOption(
    id: 'tanaman',
    name: 'Tanaman',
    type: 'tanaman',
    description: 'Pencatatan tanam, pemupukan, kondisi, dan hasil panen.',
    icon: 'eco',
    color: '#10B981',
  );

  static const values = [ayamKampung, maggotBsf, cacingTanah, lele, tanaman];

  static String nameOf(String id) {
    for (final module in values) {
      if (module.id == id) return module.name;
    }
    return id;
  }
}

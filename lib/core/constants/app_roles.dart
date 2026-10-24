abstract final class AppRoles {
  static const admin = 'admin';
  static const operatorLapangan = 'operator_lapangan';
  static const operatorKeuangan = 'operator_keuangan';

  static const legacyOperator = 'operator';
  static const legacyMitra = 'mitra';
  static const legacyPesertaEdukasi = 'peserta_edukasi';

  static const values = [admin, operatorLapangan, operatorKeuangan];

  static const legacyValues = [
    legacyOperator,
    legacyMitra,
    legacyPesertaEdukasi,
  ];

  static const defaultRole = operatorLapangan;

  static String effectiveRole(String? role) {
    final normalizedRole = role?.trim().toLowerCase();
    return switch (normalizedRole) {
      admin => admin,
      operatorLapangan || legacyOperator => operatorLapangan,
      operatorKeuangan => operatorKeuangan,
      legacyMitra => legacyMitra,
      legacyPesertaEdukasi => legacyPesertaEdukasi,
      _ => legacyPesertaEdukasi,
    };
  }

  static bool isAssignable(String role) => values.contains(effectiveRole(role));

  static String assignableRole(String role) => effectiveRole(role);

  static bool isLegacyReadOnly(String role) {
    final effective = effectiveRole(role);
    return effective == legacyMitra || effective == legacyPesertaEdukasi;
  }

  static String label(String role) {
    return switch (effectiveRole(role)) {
      admin => 'Administrator',
      operatorLapangan => 'Operator lapangan',
      operatorKeuangan => 'Operator keuangan',
      legacyMitra => 'Mitra Kebun Sei',
      _ => 'Peserta edukasi',
    };
  }
}

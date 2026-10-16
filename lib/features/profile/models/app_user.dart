import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/app_roles.dart';
import '../../../core/utils/firestore_fields.dart';

class AppUser {
  const AppUser({
    required this.uid,
    required this.name,
    required this.email,
    required this.photoUrl,
    required this.role,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  final String uid;
  final String name;
  final String email;
  final String photoUrl;
  final String role;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  String get effectiveRole => AppRoles.effectiveRole(role);
  String get roleLabel => AppRoles.label(role);

  bool get isAdmin => effectiveRole == AppRoles.admin;
  bool get isOperatorLapangan => effectiveRole == AppRoles.operatorLapangan;
  bool get isOperatorKeuangan => effectiveRole == AppRoles.operatorKeuangan;
  bool get isLegacyReadOnly => AppRoles.isLegacyReadOnly(role);

  bool get canViewDashboard => isActive;
  bool get canViewEducation => isActive;
  bool get canManageEducation => isAdmin;
  bool get canDeleteEducation => isAdmin;
  bool get canManageFarmModules => isAdmin;
  bool get canManageUsers => isAdmin;
  bool get canDeleteUsers => isAdmin;

  bool get canViewLogbooks => isActive;
  bool get canManageLogbooks => isAdmin || isOperatorLapangan;
  bool get canDeleteLogbooks => isAdmin;
  bool get canViewInventory => isActive;
  bool get canManageInventory => isAdmin || isOperatorLapangan;
  bool get canDeleteInventory => isAdmin;
  bool get canViewSchedules => isActive;
  bool get canManageSchedules => isAdmin || isOperatorLapangan;
  bool get canDeleteSchedules => isAdmin;

  bool get canViewFinance => isActive && (isAdmin || isOperatorKeuangan);
  bool get canManageFinance => isAdmin || isOperatorKeuangan;
  bool get canDeleteFinance => isAdmin || isOperatorKeuangan;
  bool get canViewFinanceDashboard => canViewFinance;
  bool get canViewRecommendations => isActive;

  bool get canManageOperations =>
      canManageLogbooks || canManageInventory || canManageSchedules;

  bool get canViewReports => isActive;

  factory AppUser.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const <String, dynamic>{};
    return AppUser(
      uid: stringField(data, const ['uid', 'id'], fallback: document.id),
      name: stringField(data, const ['name'], fallback: 'Pengguna SeiCycle'),
      email: stringField(data, const ['email']),
      photoUrl: stringField(data, const ['photoUrl', 'photo_url']),
      role: stringField(data, const [
        'role',
      ], fallback: AppRoles.legacyPesertaEdukasi),
      isActive: boolField(data, const [
        'isActive',
        'is_active',
      ], fallback: true),
      createdAt: dateTimeField(data, const ['createdAt', 'created_at']),
      updatedAt: dateTimeField(data, const ['updatedAt', 'updated_at']),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'id': uid,
      'uid': uid,
      'name': name,
      'email': email,
      'photoUrl': photoUrl,
      'role': role,
      'isActive': isActive,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }
}

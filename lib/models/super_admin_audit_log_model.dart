import 'package:flutter/material.dart';

class SuperAdminAuditLogModel {
  final String id;
  final String actorAuthUserId;
  final String? actorProfileId;
  final String actorRole;
  final String action;
  final String entityType;
  final String? entityId;
  final String? schoolId;
  final Map<String, dynamic> metadata;
  final DateTime createdAt;

  const SuperAdminAuditLogModel({
    required this.id,
    required this.actorAuthUserId,
    this.actorProfileId,
    required this.actorRole,
    required this.action,
    required this.entityType,
    this.entityId,
    this.schoolId,
    this.metadata = const {},
    required this.createdAt,
  });

  factory SuperAdminAuditLogModel.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> parsedMetadata = const {};
    if (json['metadata'] is Map) {
      parsedMetadata = Map<String, dynamic>.from(json['metadata'] as Map);
    }

    return SuperAdminAuditLogModel(
      id: json['id']?.toString() ?? '',
      actorAuthUserId: json['actor_auth_user_id']?.toString() ?? '',
      actorProfileId: json['actor_profile_id']?.toString(),
      actorRole: json['actor_role']?.toString() ?? 'unknown',
      action: json['action']?.toString() ?? '',
      entityType: json['entity_type']?.toString() ?? '',
      entityId: json['entity_id']?.toString(),
      schoolId: json['school_id']?.toString(),
      metadata: parsedMetadata,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'actor_auth_user_id': actorAuthUserId,
      if (actorProfileId != null) 'actor_profile_id': actorProfileId,
      'actor_role': actorRole,
      'action': action,
      'entity_type': entityType,
      if (entityId != null) 'entity_id': entityId,
      if (schoolId != null) 'school_id': schoolId,
      'metadata': metadata,
      'created_at': createdAt.toIso8601String(),
    };
  }

  String get actionDisplayName {
    return action
        .split('_')
        .map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '')
        .join(' ');
  }

  Color get actionColor {
    if (action.contains('fail') || action.contains('void') || action.contains('cancel') || action.contains('deactivat') || action.contains('suspend')) {
      return Colors.redAccent;
    }
    if (action.contains('create') || action.contains('complete') || action.contains('reactivat') || action.contains('paid')) {
      return Colors.green;
    }
    if (action.contains('update') || action.contains('status') || action.contains('cleanup')) {
      return Colors.blueAccent;
    }
    if (action.contains('login') || action.contains('logout')) {
      return Colors.teal;
    }
    return Colors.purpleAccent;
  }

  IconData get actionIcon {
    switch (entityType.toLowerCase()) {
      case 'school':
        return Icons.school_outlined;
      case 'billing':
      case 'invoice':
      case 'payment':
        return Icons.receipt_long_outlined;
      case 'provisioning':
        return Icons.rocket_launch_outlined;
      case 'app':
        return Icons.apps_outlined;
      case 'subscription':
        return Icons.card_membership_outlined;
      case 'auth':
      case 'user':
      case 'admin':
        return Icons.person_outline;
      default:
        return Icons.history_outlined;
    }
  }
}

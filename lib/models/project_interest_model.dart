import 'package:cloud_firestore/cloud_firestore.dart';

/// Lead from `projects/{projectId}/interests` — aligned with iOS `ProjectInterest`.
class ProjectInterestModel {
  const ProjectInterestModel({
    required this.id,
    required this.projectId,
    this.userId,
    required this.name,
    required this.email,
    this.phone,
    this.message,
    required this.createdAt,
    this.contactedAt,
    this.unitId,
    required this.conversionStatusRaw,
    this.notes,
    required this.lastUpdated,
    this.contactUnlocked = true,
    this.previewSnippet,
    this.intentTypeRaw,
  });

  final String id;
  final String projectId;
  final String? userId;
  final String name;
  final String email;
  final String? phone;
  final String? message;
  final DateTime createdAt;
  final DateTime? contactedAt;
  final String? unitId;
  final String conversionStatusRaw;
  final String? notes;
  final DateTime lastUpdated;
  final bool contactUnlocked;
  final String? previewSnippet;
  /// iOS `LeadIntentType` raw string from `intentType` / `intent_type`.
  final String? intentTypeRaw;

  /// iOS `LeadIntentType.displayName` — short label for chips.
  String get intentDisplayName {
    final s = intentTypeRaw?.trim().toLowerCase() ?? '';
    switch (s) {
      case 'inquiry':
        return 'Inquiry';
      case 'schedule_tour':
      case 'schedule tour':
        return 'Schedule tour';
      case 'request_info':
      case 'request info':
        return 'Request info';
      default:
        if (s.isEmpty) return 'Inquiry';
        return s[0].toUpperCase() + s.substring(1);
    }
  }

  String get conversionTitle {
    final s = conversionStatusRaw.trim().toLowerCase();
    switch (s) {
      case 'new':
        return 'New';
      case 'contacted':
        return 'Contacted';
      case 'viewing':
        return 'Viewing';
      case 'negotiating':
        return 'Negotiating';
      case 'reserved':
        return 'Reserved';
      case 'closed':
        return 'Closed';
      default:
        return s.isEmpty ? '—' : s[0].toUpperCase() + s.substring(1);
    }
  }

  static DateTime _ts(dynamic v, DateTime fallback) {
    if (v is Timestamp) return v.toDate();
    return fallback;
  }

  static ProjectInterestModel fromFirestore(
    String documentId,
    Map<String, dynamic> data,
  ) {
    final createdAt = _ts(data['createdAt'], DateTime.now());
    final lastUpdated = _ts(data['lastUpdated'], createdAt);
    final contactedAt = data['contactedAt'] is Timestamp
        ? (data['contactedAt'] as Timestamp).toDate()
        : null;

    final rawEmail = data['email'] as String?;
    final explicitUnlocked = data['contactUnlocked'] as bool?;
    final contactUnlocked = explicitUnlocked ?? (rawEmail?.isNotEmpty == true);

    var name = data['name'] as String? ?? '';
    var email = rawEmail ?? '';

    if (!contactUnlocked) {
      if (name.isEmpty) name = 'New lead';
    } else if (name.isEmpty || email.isEmpty) {
      if (name.isEmpty) name = '—';
      if (email.isEmpty) email = '—';
    }

    return ProjectInterestModel(
      id: documentId,
      projectId: data['projectId'] as String? ?? '',
      userId: data['userId'] as String?,
      name: name,
      email: email,
      phone: data['phone'] as String?,
      message: data['message'] as String?,
      createdAt: createdAt,
      contactedAt: contactedAt,
      unitId: data['unitId'] as String?,
      conversionStatusRaw:
          data['conversionStatus'] as String? ?? 'new',
      notes: data['notes'] as String?,
      lastUpdated: lastUpdated,
      contactUnlocked: contactUnlocked,
      previewSnippet: data['previewSnippet'] as String? ??
          data['preview_snippet'] as String?,
      intentTypeRaw: (data['intentType'] ?? data['intent_type']) as String?,
    );
  }
}

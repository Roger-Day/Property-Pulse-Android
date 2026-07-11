import 'package:cloud_firestore/cloud_firestore.dart';

/// Mirrors iOS `PropertyDocumentType` — raw values are shared with the
/// `documentType` Cloud Function payload, so they must stay exact strings.
enum PropertyDocumentType {
  floorPlan('floorPlan', 'Floor Plan'),
  inspectionReport('inspectionReport', 'Inspection Report'),
  other('other', 'Other');

  const PropertyDocumentType(this.rawValue, this.displayName);

  final String rawValue;
  final String displayName;

  static PropertyDocumentType fromRaw(String? raw) {
    return PropertyDocumentType.values.firstWhere(
      (t) => t.rawValue == raw,
      orElse: () => PropertyDocumentType.other,
    );
  }
}

/// `properties/{propertyId}/documents/{docId}` — written server-side only by
/// the `confirmDocumentUpload` Cloud Function. Mirrors iOS `PropertyDocument`.
class PropertyDocumentModel {
  const PropertyDocumentModel({
    required this.id,
    required this.propertyId,
    required this.name,
    required this.url,
    required this.type,
    required this.uploadedAt,
    this.filePath,
    this.storageAccess,
  });

  final String id;
  final String propertyId;
  final String name;
  final String url;
  final PropertyDocumentType type;
  final DateTime uploadedAt;
  final String? filePath;
  final String? storageAccess;

  /// When true, there is no public Storage URL — fetch a short-lived signed
  /// URL via `getPropertyListingDocumentSignedURL` instead of using [url].
  bool get usesSignedURL {
    if (storageAccess == 'signed') return true;
    if (url.isNotEmpty) return false;
    return filePath != null && filePath!.isNotEmpty;
  }

  static PropertyDocumentModel? fromFirestore(
    String id,
    String propertyId,
    Map<String, dynamic> data,
  ) {
    final name = (data['documentName'] as String?) ??
        (data['name'] as String?) ??
        'Document';
    final url = (data['url'] as String?) ?? (data['fileURL'] as String?) ?? '';
    final typeRaw =
        (data['documentType'] as String?) ?? (data['type'] as String?);
    final filePath = data['filePath'] as String?;
    final storageAccess = data['storageAccess'] as String?;

    final hasLegacyUrl = url.isNotEmpty;
    final usesSigned = storageAccess == 'signed' ||
        (!hasLegacyUrl && filePath != null && filePath.isNotEmpty);
    if (!hasLegacyUrl && !usesSigned) return null;

    final uploadedAtRaw = data['uploadedAt'];
    final uploadedAt = uploadedAtRaw is Timestamp
        ? uploadedAtRaw.toDate()
        : DateTime.now();

    return PropertyDocumentModel(
      id: id,
      propertyId: propertyId,
      name: name,
      url: url,
      type: PropertyDocumentType.fromRaw(typeRaw),
      uploadedAt: uploadedAt,
      filePath: filePath,
      storageAccess: storageAccess,
    );
  }
}

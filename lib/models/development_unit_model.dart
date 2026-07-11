import 'package:cloud_firestore/cloud_firestore.dart';

/// Per-unit inventory row — iOS `DevelopmentUnit` at `developments/{id}/units`.
enum DevelopmentUnitStatus {
  available,
  reserved,
  sold,
  ;

  static DevelopmentUnitStatus? fromRaw(String? raw) {
    if (raw == null) return null;
    final s = raw.trim().toLowerCase();
    if (s.isEmpty) return null;
    switch (s) {
      case 'available':
      case 'avail':
      case 'open':
        return DevelopmentUnitStatus.available;
      case 'reserved':
      case 'reservation':
      case 'on_hold':
      case 'onhold':
      case 'hold':
        return DevelopmentUnitStatus.reserved;
      case 'sold':
      case 'closed':
        return DevelopmentUnitStatus.sold;
      default:
        return null;
    }
  }

  String get title {
    switch (this) {
      case DevelopmentUnitStatus.available:
        return 'Available';
      case DevelopmentUnitStatus.reserved:
        return 'Reserved';
      case DevelopmentUnitStatus.sold:
        return 'Sold';
    }
  }
}

class DevelopmentUnitModel {
  const DevelopmentUnitModel({
    required this.id,
    required this.developmentId,
    required this.unitNumber,
    required this.type,
    this.projectUnitTypeId,
    required this.price,
    required this.status,
    this.buyerId,
    this.reservedForInterestId,
    required this.updatedAt,
  });

  final String id;
  final String developmentId;
  final String unitNumber;
  final String type;
  final String? projectUnitTypeId;
  final double price;
  final DevelopmentUnitStatus status;
  final String? buyerId;
  final String? reservedForInterestId;
  final DateTime updatedAt;

  /// Lead-held units (`reservedForInterestId`) count as reserved unless sold.
  DevelopmentUnitStatus get effectiveStatus {
    if (status == DevelopmentUnitStatus.sold) {
      return DevelopmentUnitStatus.sold;
    }
    final rid = reservedForInterestId?.trim();
    if (rid != null && rid.isNotEmpty) {
      return DevelopmentUnitStatus.reserved;
    }
    return status;
  }

  static DevelopmentUnitModel? fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    if (data == null) return null;

    final developmentId = data['developmentId'] as String?;
    final unitNumber = data['unitNumber'] as String?;
    final type = data['type'] as String?;
    final statusRaw = data['status'] as String?;
    final status = DevelopmentUnitStatus.fromRaw(statusRaw);
    if (developmentId == null ||
        unitNumber == null ||
        type == null ||
        status == null) {
      return null;
    }

    final price = (data['price'] as num?)?.toDouble() ??
        (data['price'] as int?)?.toDouble();
    if (price == null) return null;

    final id = (data['id'] as String?)?.trim().isNotEmpty == true
        ? data['id'] as String
        : doc.id;

    DateTime updatedAt = DateTime.now();
    final u = data['updatedAt'];
    if (u is Timestamp) updatedAt = u.toDate();

    final puid = (data['projectUnitTypeId'] ?? data['project_unit_type_id'])
        as String?;
    final projectUnitTypeId =
        puid?.trim().isEmpty == true ? null : puid?.trim();

    final rid = data['reservedForInterestId'] as String?;
    final reservedForInterestId =
        rid?.trim().isEmpty == true ? null : rid?.trim();

    return DevelopmentUnitModel(
      id: id,
      developmentId: developmentId,
      unitNumber: unitNumber,
      type: type,
      projectUnitTypeId: projectUnitTypeId,
      price: price,
      status: status,
      buyerId: data['buyerId'] as String?,
      reservedForInterestId: reservedForInterestId,
      updatedAt: updatedAt,
    );
  }
}

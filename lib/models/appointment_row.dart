import 'package:cloud_firestore/cloud_firestore.dart';

/// Canonical appointment types — mirrors iOS `AppointmentType` raw values
/// exactly (`Models/Appointment.swift`). All Android booking forms must use
/// this list so a value written on Android always decodes on iOS.
const List<String> kAppointmentTypes = <String>[
  'Property Viewing',
  'Consultation',
  'Open House',
  'Virtual Tour',
  'Contract Signing',
  'Inspection',
  'Other',
];

class AppointmentRow {
  AppointmentRow({
    required this.id,
    required this.propertyId,
    required this.propertyTitle,
    required this.propertyAddress,
    required this.userId,
    required this.userName,
    required this.userEmail,
    required this.realtorId,
    required this.realtorName,
    required this.realtorEmail,
    required this.appointmentType,
    required this.date,
    required this.duration,
    required this.status,
    required this.notes,
    required this.createdAt,
    required this.chatEnabled,
  });

  final String id;
  final String propertyId;
  final String propertyTitle;
  final String propertyAddress;
  final String userId;
  final String userName;
  final String userEmail;
  final String realtorId;
  final String realtorName;
  final String realtorEmail;
  final String appointmentType;
  final DateTime date;
  final int duration;
  final String status;
  final String notes;
  final DateTime? createdAt;
  final bool chatEnabled;

  factory AppointmentRow.fromDoc(
    String id,
    Map<String, dynamic> data,
  ) {
    DateTime parseDate(dynamic value, {DateTime? fallback}) {
      if (value is Timestamp) return value.toDate();
      if (value is DateTime) return value;
      return fallback ?? DateTime.now();
    }

    DateTime? parseOptDate(dynamic value) {
      if (value is Timestamp) return value.toDate();
      if (value is DateTime) return value;
      return null;
    }

    return AppointmentRow(
      id: id,
      propertyId: data['propertyId'] as String? ?? '',
      propertyTitle: data['propertyTitle'] as String? ?? 'Property',
      propertyAddress: data['propertyAddress'] as String? ?? '',
      userId: data['userId'] as String? ?? '',
      userName: data['userName'] as String? ?? 'Client',
      userEmail: data['userEmail'] as String? ?? '',
      realtorId: data['realtorId'] as String? ?? '',
      realtorName: data['realtorName'] as String? ?? 'Agent',
      realtorEmail: data['realtorEmail'] as String? ?? '',
      appointmentType:
          data['appointmentType'] as String? ?? 'Property Viewing',
      date: parseDate(data['date']),
      duration: (data['duration'] as num?)?.toInt() ?? 60,
      status: (data['status'] as String? ?? 'Requested'),
      notes: data['notes'] as String? ?? '',
      createdAt: parseOptDate(data['createdAt']),
      chatEnabled: data['chatEnabled'] as bool? ?? true,
    );
  }

  bool get isPast => date.isBefore(DateTime.now());

  /// Mirrors iOS `Appointment.isExpired` — true when the slot has passed
  /// without being confirmed/approved/actioned further.
  bool get isExpired {
    final end = date.add(Duration(minutes: duration));
    final s = status.toLowerCase();
    return end.isBefore(DateTime.now()) &&
        (s == 'requested' || s == 'approved');
  }

  /// Mirrors iOS `Appointment.effectiveStatus` — substitutes "Expired" for
  /// display when the slot has passed unactioned.
  String get displayStatus {
    if (isExpired) return 'Expired';
    switch (status.toLowerCase()) {
      case 'requested':
        return 'Awaiting Approval';
      case 'approved':
        return 'Approved';
      case 'rejected':
        return 'Rejected';
      case 'confirmed':
        return 'Confirmed';
      case 'completed':
        return 'Completed';
      case 'cancelled':
      case 'canceled':
        return 'Cancelled';
      default:
        return status;
    }
  }
}

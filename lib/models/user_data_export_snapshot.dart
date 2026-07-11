import 'package:intl/intl.dart';

/// Client-side export bundle — mirrors iOS `UserDataExport` fields used in UI + CSV.
class UserDataExportSnapshot {
  UserDataExportSnapshot({
    required this.exportDate,
    required this.fullName,
    required this.email,
    required this.role,
    this.phone,
    required this.savedProperties,
    required this.messages,
    required this.appointments,
  });

  final DateTime exportDate;
  final String fullName;
  final String email;
  final String role;
  final String? phone;
  final List<PropertyExportRow> savedProperties;
  final List<MessageExportRow> messages;
  final List<AppointmentExportRow> appointments;

  /// Mirrors iOS `UserDataExport.csvData` structure (UTF-8 plain text).
  String get csvDocument {
    final buf = StringBuffer()
      ..writeln('User Data Export')
      ..writeln('Export Date: ${exportDate.toIso8601String()}')
      ..writeln()
      ..writeln('User Information')
      ..writeln('Name,Email,Role,Phone')
      ..writeln(
        '${_csv(fullName)},${_csv(email)},${_csv(role)},${_csv(phone ?? '')}',
      )
      ..writeln()
      ..writeln('Saved Properties')
      ..writeln('Title,Price,Location,Status');
    for (final p in savedProperties) {
      buf.writeln(
        '${_csv(p.title)},${_csv(p.priceLabel)},${_csv(p.location)},${_csv(p.status)}',
      );
    }
    buf
      ..writeln()
      ..writeln('Messages')
      ..writeln('SenderId,Content,Date');
    for (final m in messages) {
      final dateStr =
          m.createdAt != null ? m.createdAt!.toIso8601String() : '';
      buf.writeln(
        '${_csv(m.senderId)},${_csv(m.text)},${_csv(dateStr)}',
      );
    }
    buf
      ..writeln()
      ..writeln('Appointments')
      ..writeln('PropertyId,Date,Status');
    for (final a in appointments) {
      final dateStr = a.date != null ? a.date!.toIso8601String() : '';
      buf.writeln(
        '${_csv(a.propertyId)},${_csv(dateStr)},${_csv(a.status)}',
      );
    }
    return buf.toString();
  }

  static String _csv(String s) {
    if (s.contains(',') || s.contains('"') || s.contains('\n')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }

  static String formatMedium(DateTime d) =>
      DateFormat.yMMMd().add_jm().format(d.toLocal());
}

class PropertyExportRow {
  PropertyExportRow({
    required this.title,
    required this.location,
    required this.priceLabel,
    required this.status,
  });

  final String title;
  final String location;
  final String priceLabel;
  final String status;
}

class MessageExportRow {
  MessageExportRow({
    required this.senderId,
    required this.text,
    this.createdAt,
  });

  final String senderId;
  final String text;
  final DateTime? createdAt;
}

class AppointmentExportRow {
  AppointmentExportRow({
    required this.propertyId,
    this.date,
    required this.status,
  });

  final String propertyId;
  final DateTime? date;
  final String status;
}

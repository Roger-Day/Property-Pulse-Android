import 'package:cloud_functions/cloud_functions.dart';
import 'package:http/http.dart' as http;

import '../models/property_document_model.dart';

/// Uploads/reads listing documents (floor plans, inspection reports) via the
/// same Cloud Functions iOS uses — `DocumentAndReportService.swift` —
/// so Storage never needs to be world-readable/writable for these files.
class PropertyDocumentService {
  PropertyDocumentService({FirebaseFunctions? functions})
      : _fns = functions ?? FirebaseFunctions.instanceFor(region: 'us-central1');

  final FirebaseFunctions _fns;

  /// Requests a short-lived signed PUT URL for a new document.
  Future<({String uploadUrl, String filePath})> generateUploadUrl({
    required String propertyId,
    required String documentName,
    required PropertyDocumentType documentType,
  }) async {
    final result = await _fns.httpsCallable('generateDocumentUploadURL').call(
      <String, dynamic>{
        'propertyId': propertyId,
        'documentName': documentName,
        'documentType': documentType.rawValue,
      },
    );
    final data = Map<String, dynamic>.from(result.data as Map);
    final uploadUrl = data['uploadURL'] as String?;
    final filePath = data['filePath'] as String?;
    if (uploadUrl == null || filePath == null) {
      throw StateError('generateDocumentUploadURL returned no upload URL.');
    }
    return (uploadUrl: uploadUrl, filePath: filePath);
  }

  /// Raw PUT of the PDF bytes to the signed URL from [generateUploadUrl].
  Future<void> uploadBytes({
    required String uploadUrl,
    required List<int> bytes,
  }) async {
    final response = await http.put(
      Uri.parse(uploadUrl),
      headers: {'Content-Type': 'application/pdf'},
      body: bytes,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Document upload failed (${response.statusCode}).');
    }
  }

  /// Writes `properties/{propertyId}/documents/{id}` metadata server-side
  /// once the file is in Storage.
  Future<void> confirmUpload({
    required String propertyId,
    required String filePath,
    required String documentName,
    required PropertyDocumentType documentType,
  }) async {
    await _fns.httpsCallable('confirmDocumentUpload').call(
      <String, dynamic>{
        'propertyId': propertyId,
        'filePath': filePath,
        'documentName': documentName,
        'documentType': documentType.rawValue,
      },
    );
  }

  /// Short-lived signed read URL — Storage is not world-readable, so this is
  /// required whenever [PropertyDocumentModel.usesSignedURL] is true.
  Future<String> signedDownloadUrl({
    required String propertyId,
    required String documentId,
  }) async {
    final result =
        await _fns.httpsCallable('getPropertyListingDocumentSignedURL').call(
      <String, dynamic>{
        'propertyId': propertyId,
        'documentId': documentId,
      },
    );
    final data = Map<String, dynamic>.from(result.data as Map);
    final url = data['signedUrl'] as String?;
    if (url == null) {
      throw StateError('getPropertyListingDocumentSignedURL returned no URL.');
    }
    return url;
  }

  Future<void> deleteDocument({
    required String propertyId,
    required String documentId,
  }) async {
    await _fns.httpsCallable('deleteDocument').call(
      <String, dynamic>{
        'propertyId': propertyId,
        'documentId': documentId,
      },
    );
  }
}

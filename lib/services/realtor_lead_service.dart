import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/realtor_lead_model.dart';

/// Mirrors iOS `RealtorLeadService` — reads/writes from `realtor_leads` collection.
class RealtorLeadService extends ChangeNotifier {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  List<RealtorLead> _leads = [];
  List<SavedResponse> _savedResponses = [];
  String? errorMessage;

  StreamSubscription<QuerySnapshot>? _leadsSub;
  StreamSubscription<QuerySnapshot>? _responsesSub;

  List<RealtorLead> get leads => _leads;
  List<RealtorLead> get highPriorityLeads =>
      _leads.where((l) => l.priority == RealtorLeadPriority.high).toList();
  List<SavedResponse> get savedResponses => _savedResponses;

  void startListening(String realtorId) {
    _leadsSub = _db
        .collection('realtor_leads')
        .where('realtorId', isEqualTo: realtorId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen(
      (snap) {
        _leads = snap.docs.map(RealtorLead.fromFirestore).toList();
        notifyListeners();
      },
      onError: (e) {
        errorMessage = e.toString();
        notifyListeners();
      },
    );

    _responsesSub = _db
        .collection('realtors')
        .doc(realtorId)
        .collection('saved_responses')
        .orderBy('createdAt', descending: false)
        .snapshots()
        .listen(
      (snap) {
        _savedResponses = snap.docs.map(SavedResponse.fromFirestore).toList();
        notifyListeners();
      },
      onError: (_) {},
    );
  }

  void stopListening() {
    _leadsSub?.cancel();
    _responsesSub?.cancel();
  }

  @override
  void dispose() {
    stopListening();
    super.dispose();
  }

  Future<void> createLead(RealtorLead lead) async {
    try {
      await _db.collection('realtor_leads').add(lead.toFirestore());
    } catch (e) {
      errorMessage = e.toString();
      notifyListeners();
    }
  }

  Future<void> updateLeadStatus(RealtorLead lead, RealtorLeadStatus status) async {
    if (lead.id == null) return;
    try {
      await _db
          .collection('realtor_leads')
          .doc(lead.id)
          .update({'status': status.firestoreValue});
    } catch (e) {
      errorMessage = e.toString();
      notifyListeners();
    }
  }

  Future<void> updateLeadPriority(
      RealtorLead lead, RealtorLeadPriority priority) async {
    if (lead.id == null) return;
    try {
      await _db
          .collection('realtor_leads')
          .doc(lead.id)
          .update({'priority': priority.name});
    } catch (e) {
      errorMessage = e.toString();
      notifyListeners();
    }
  }

  Future<void> updateLeadNotes(RealtorLead lead, String notes) async {
    if (lead.id == null) return;
    try {
      await _db
          .collection('realtor_leads')
          .doc(lead.id)
          .update({'notes': notes});
    } catch (e) {
      errorMessage = e.toString();
      notifyListeners();
    }
  }

  Future<void> createSavedResponse({
    required String realtorId,
    required String title,
    required String body,
  }) async {
    try {
      await _db
          .collection('realtors')
          .doc(realtorId)
          .collection('saved_responses')
          .add(SavedResponse(title: title, body: body).toFirestore());
    } catch (e) {
      errorMessage = e.toString();
      notifyListeners();
    }
  }

  Future<void> deleteSavedResponse({
    required String realtorId,
    required SavedResponse response,
  }) async {
    if (response.id == null) return;
    try {
      await _db
          .collection('realtors')
          .doc(realtorId)
          .collection('saved_responses')
          .doc(response.id)
          .delete();
    } catch (e) {
      errorMessage = e.toString();
      notifyListeners();
    }
  }
}

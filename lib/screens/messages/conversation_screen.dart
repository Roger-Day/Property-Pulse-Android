import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_constants.dart';
import '../../models/property_model.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/property_repository.dart';
import '../../services/analytics_service.dart';
import '../../services/messaging_service.dart';
import '../../widgets/full_screen_image_gallery.dart';
import '../../widgets/messaging/message_templates_sheet.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Data helpers
// ─────────────────────────────────────────────────────────────────────────────

/// A locally-held message shown before Firestore confirms (optimistic UI).
class _PendingMsg {
  _PendingMsg({
    required this.id,
    required this.text,
    required this.createdAt,
    this.localImageFile,
    this.uploadedImageUrl,
    this.uploadProgress = 0,
    this.failed = false,
    this.propertyId,
    this.propertyTitle,
  });

  final String id;
  final String text;
  final DateTime createdAt;
  final File? localImageFile;
  String? uploadedImageUrl;
  double uploadProgress; // 0.0–1.0
  bool failed;
  /// Mirrors iOS Message.propertyId — property context attached to this message
  final String? propertyId;
  final String? propertyTitle;
}

/// A single item that the list view renders — either a Firestore message or a
/// local pending message.
class _Item {
  const _Item({
    required this.createdAt,
    this.docId,
    this.data,
    this.pending,
    this.showDateSeparator = false,
    this.isFirstInGroup = true,
    this.isLastInGroup = true,
  });

  final DateTime createdAt;
  final String? docId; // null for pending
  final Map<String, dynamic>? data; // null for pending
  final _PendingMsg? pending;
  final bool showDateSeparator;
  final bool isFirstInGroup;
  final bool isLastInGroup;

  bool get isPending => pending != null;

  String get senderId =>
      data?['senderId'] as String? ?? pending?.id ?? '';

  String get text =>
      data?['text'] as String? ?? pending?.text ?? '';

  String? get imageUrl =>
      data?['imageUrl'] as String? ??
      // iOS writes image attachments as `attachmentURL` (Message.swift)
      data?['attachmentURL'] as String? ??
      pending?.uploadedImageUrl;

  File? get localImage => pending?.localImageFile;

  bool get isImage =>
      (data?['type'] == 'image') || (pending?.localImageFile != null);

  /// Property context attached to this message (mirrors iOS Message.propertyId)
  String? get messagePropertyId =>
      data?['propertyId'] as String? ?? pending?.propertyId;
}

// 5-minute gap threshold for grouping (matches iOS)
const _kGroupGapMinutes = 5;

/// Build merged + annotated item list from Firestore docs and local pending msgs.
List<_Item> _buildItems(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  List<_PendingMsg> pending,
  String currentUserId,
) {
  // Convert docs to raw records
  final allRaw = <({String senderId, DateTime dt, String? docId, Map<String, dynamic>? data, _PendingMsg? pending})>[];

  for (final doc in docs) {
    final d = doc.data();
    final ts = d['createdAt'];
    DateTime dt = DateTime.now();
    if (ts is Timestamp) dt = ts.toDate();
    allRaw.add((senderId: d['senderId'] as String? ?? '', dt: dt, docId: doc.id, data: d, pending: null));
  }

  // Remove pending messages that already appear in Firestore docs
  // (de-dupe by approximate time + content)
  final confirmedTexts = docs
      .map((d) => '${d.data()['senderId']}|${d.data()['text']}')
      .toSet();

  for (final p in pending) {
    final key = '$currentUserId|${p.text}';
    if (!confirmedTexts.contains(key)) {
      allRaw.add((senderId: currentUserId, dt: p.createdAt, docId: null, data: null, pending: p));
    }
  }

  // Sort by time
  allRaw.sort((a, b) => a.dt.compareTo(b.dt));

  // Annotate items
  final items = <_Item>[];
  for (var i = 0; i < allRaw.length; i++) {
    final cur = allRaw[i];
    final prev = i > 0 ? allRaw[i - 1] : null;
    final next = i < allRaw.length - 1 ? allRaw[i + 1] : null;

    // Date separator
    final showSep = prev == null ||
        !_sameDay(prev.dt, cur.dt);

    // Grouping
    final isFirst = prev == null ||
        prev.senderId != cur.senderId ||
        cur.dt.difference(prev.dt).inMinutes >= _kGroupGapMinutes;

    final isLast = next == null ||
        next.senderId != cur.senderId ||
        next.dt.difference(cur.dt).inMinutes >= _kGroupGapMinutes;

    items.add(_Item(
      createdAt: cur.dt,
      docId: cur.docId,
      data: cur.data,
      pending: cur.pending,
      showDateSeparator: showSep,
      isFirstInGroup: isFirst,
      isLastInGroup: isLast,
    ));
  }
  return items;
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _dateHeader(DateTime dt) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));
  final msgDay = DateTime(dt.year, dt.month, dt.day);
  if (msgDay == today) return 'Today';
  if (msgDay == yesterday) return 'Yesterday';
  if (now.difference(msgDay).inDays < 7) return DateFormat.EEEE().format(dt);
  return DateFormat.yMMMd().format(dt);
}

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────

class ConversationScreen extends StatefulWidget {
  const ConversationScreen({
    super.key,
    required this.threadId,
    required this.currentUserId,
  });

  final String threadId;
  final String currentUserId;

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final _imagePicker = ImagePicker();

  bool _sending = false;
  bool _peerIsTyping = false;
  final List<_PendingMsg> _pending = [];

  StreamSubscription<bool>? _typingSub;
  Timer? _typingTimer;
  bool _iAmTyping = false;

  CollectionReference<Map<String, dynamic>> get _messagesRef =>
      FirebaseFirestore.instance
          .collection(AppConstants.conversationsCollection)
          .doc(widget.threadId)
          .collection('messages');

  DocumentReference<Map<String, dynamic>> get _convRef =>
      FirebaseFirestore.instance
          .collection(AppConstants.conversationsCollection)
          .doc(widget.threadId);

  // ── Lifecycle ───────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _markThreadRead());
    _inputController.addListener(_onTextChanged);
    _startTypingListener();
  }

  @override
  void dispose() {
    _clearTyping();
    _typingTimer?.cancel();
    _typingSub?.cancel();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ── Thread helpers ──────────────────────────────────────────────────────────

  Future<void> _markThreadRead() async {
    try {
      await _convRef.update({
        'unreadCounts.${widget.currentUserId}': 0,
        // iOS-parity: lastReadAtByUser map used for read receipts
        'lastReadAtByUser.${widget.currentUserId}':
            FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  String _otherId(Map<String, dynamic>? data) {
    if (data == null) return '';
    for (final key in ['participantIds', 'participants']) {
      final v = data[key];
      if (v is List && v.isNotEmpty) {
        return v
            .map((e) => e.toString())
            .firstWhere((id) => id != widget.currentUserId, orElse: () => '');
      }
    }
    return '';
  }

  Map<String, dynamic> _otherProfile(
      Map<String, dynamic>? data, String otherId) {
    if (data == null || otherId.isEmpty) return {};
    final profiles = data['participantProfiles'];
    if (profiles is Map) {
      final p = profiles[otherId];
      if (p is Map) return Map<String, dynamic>.from(p);
    }
    final legacy = data['participants'];
    if (legacy is Map) {
      final p = legacy[otherId];
      if (p is Map) return Map<String, dynamic>.from(p);
    }
    return {};
  }

  // ── Typing indicators ───────────────────────────────────────────────────────

  void _startTypingListener() {
    _typingSub = MessagingService.watchPeerTyping(
      db: FirebaseFirestore.instance,
      threadId: widget.threadId,
      myUserId: widget.currentUserId,
    ).listen((typing) {
      if (mounted) setState(() => _peerIsTyping = typing);
    });
  }

  void _onTextChanged() {
    final hasText = _inputController.text.trim().isNotEmpty;
    if (hasText && !_iAmTyping) {
      _iAmTyping = true;
      _setTypingStatus(true);
    }
    _typingTimer?.cancel();
    if (hasText) {
      // Stop typing indicator after 3 s idle
      _typingTimer = Timer(const Duration(seconds: 3), _clearTyping);
    } else {
      _clearTyping();
    }
  }

  void _setTypingStatus(bool typing) {
    MessagingService.setTypingStatus(
      db: FirebaseFirestore.instance,
      threadId: widget.threadId,
      userId: widget.currentUserId,
      isTyping: typing,
    );
  }

  void _clearTyping() {
    if (_iAmTyping) {
      _iAmTyping = false;
      _setTypingStatus(false);
    }
  }

  // ── Send text ───────────────────────────────────────────────────────────────

  Future<void> _send() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _sending) return;

    HapticFeedback.lightImpact();
    _inputController.clear();
    _clearTyping();

    final pending = _PendingMsg(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      text: text,
      createdAt: DateTime.now(),
    );
    setState(() {
      _pending.add(pending);
      _sending = true;
    });
    _scrollToBottom();

    try {
      await MessagingService.sendTextMessage(
        db: FirebaseFirestore.instance,
        threadId: widget.threadId,
        senderId: widget.currentUserId,
        text: text,
      );
      if (mounted) setState(() => _pending.remove(pending));
      unawaited(AnalyticsService.logMessageSent(widget.threadId));
    } catch (e) {
      if (mounted) {
        setState(() => pending.failed = true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Message not delivered'),
            action: SnackBarAction(
              label: 'Retry',
              onPressed: () {
                setState(() => _pending.remove(pending));
                _inputController.text = text;
              },
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // ── Send image ──────────────────────────────────────────────────────────────

  Future<void> _pickImage() async {
    final picked = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 75,
      maxWidth: 1280,
      maxHeight: 1280,
    );
    if (picked == null || !mounted) return;

    final file = File(picked.path);
    final pending = _PendingMsg(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      text: '',
      createdAt: DateTime.now(),
      localImageFile: file,
    );

    setState(() => _pending.add(pending));
    _scrollToBottom();

    try {
      final url = await MessagingService.uploadMessageImage(
        threadId: widget.threadId,
        file: file,
        onProgress: (p) {
          if (mounted) setState(() => pending.uploadProgress = p);
        },
      );
      pending.uploadedImageUrl = url;

      await MessagingService.sendImageMessage(
        db: FirebaseFirestore.instance,
        threadId: widget.threadId,
        senderId: widget.currentUserId,
        imageUrl: url,
      );

      if (mounted) setState(() => _pending.remove(pending));
      unawaited(AnalyticsService.logMessageSent(widget.threadId, hasImage: true));
    } catch (e) {
      if (mounted) {
        setState(() => pending.failed = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Image could not be sent')),
        );
      }
    }
  }

  // ── Message deletion ────────────────────────────────────────────────────────

  Future<void> _deleteMessage(String docId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete message?'),
        content:
            const Text('This message will be removed for everyone in this conversation.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await MessagingService.deleteMessage(
        db: FirebaseFirestore.instance,
        threadId: widget.threadId,
        messageId: docId,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete: $e')),
        );
      }
    }
  }

  // ── Property share ──────────────────────────────────────────────────────────
  // Mirrors iOS ChatView: tap house icon → pick property → send message with
  // propertyId attached → PropertyBadge renders below the bubble.

  void _showPropertyPicker(BuildContext ctx) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _PropertyPickerForChat(
        onSelected: (propertyId, propertyTitle) {
          Navigator.of(ctx).pop();
          _sendWithProperty(
              propertyId: propertyId, propertyTitle: propertyTitle);
        },
      ),
    );
  }

  Future<void> _sendWithProperty({
    required String propertyId,
    required String propertyTitle,
  }) async {
    final auth = context.read<AuthProvider>();
    final uid = auth.user?.uid;
    if (uid == null) return;

    // Add optimistic pending message with property context
    final pending = _PendingMsg(
      id: FirebaseFirestore.instance.collection('_').doc().id,
      text: '🏠 $propertyTitle',
      createdAt: DateTime.now(),
      propertyId: propertyId,
      propertyTitle: propertyTitle,
    );
    setState(() => _pending.add(pending));
    _scrollToBottom();

    try {
      await MessagingService.sendMessage(
        db: FirebaseFirestore.instance,
        threadId: widget.threadId,
        senderId: uid,
        text: '🏠 $propertyTitle',
        propertyId: propertyId,
        clientId: pending.id,
      );
      if (mounted) {
        setState(() => _pending.removeWhere((p) => p.id == pending.id));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          final idx = _pending.indexWhere((p) => p.id == pending.id);
          if (idx != -1) _pending[idx].failed = true;
        });
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to send: $e')));
      }
    }
  }

  // ── Scroll ──────────────────────────────────────────────────────────────────

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ── Template ────────────────────────────────────────────────────────────────

  void _insertTemplate(String content) {
    final cur = _inputController.text;
    _inputController.text =
        cur.trim().isEmpty ? content : '$cur\n\n$content';
    _inputController.selection =
        TextSelection.collapsed(offset: _inputController.text.length);
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _convRef.snapshots(),
      builder: (context, convSnap) {
        final data = convSnap.data?.data();
        final propertyId = (data?['propertyId'] as String?)?.trim() ?? '';
        final convPropertyTitle = data?['propertyTitle'] as String? ?? '';

        if (propertyId.isEmpty) {
          return _buildConversationScaffold(
            context,
            data: data,
            propertyId: '',
            propertyModel: null,
            convPropertyTitle: convPropertyTitle,
          );
        }

        return StreamBuilder<PropertyModel?>(
          stream: context.read<PropertyRepository>().watchProperty(propertyId),
          builder: (context, propSnap) {
            return _buildConversationScaffold(
              context,
              data: data,
              propertyId: propertyId,
              propertyModel: propSnap.data,
              convPropertyTitle: convPropertyTitle,
            );
          },
        );
      },
    );
  }

  /// Parity with iOS [ChatView] property header: show live listing when
  /// [propertyId] is set (conversation may only store id, not title).
  Widget _buildConversationScaffold(
    BuildContext context, {
    required Map<String, dynamic>? data,
    required String propertyId,
    required PropertyModel? propertyModel,
    required String convPropertyTitle,
  }) {
    final otherId = _otherId(data);
    final otherProfile = _otherProfile(data, otherId);
    final otherName =
        otherProfile['displayName'] as String? ?? 'Conversation';
    final otherPhoto = otherProfile['photoURL'] as String?;

    final resolvedListingTitle = propertyModel?.title ??
        (convPropertyTitle.trim().isNotEmpty ? convPropertyTitle : '');
    final showListingInAppBar =
        propertyId.isNotEmpty && resolvedListingTitle.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        leading: BackButton(
          onPressed: () {
            _markThreadRead();
            Navigator.of(context).pop();
          },
        ),
        title: Row(
          children: [
            _PeerAvatar(name: otherName, photoUrl: otherPhoto, radius: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    otherName,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (showListingInAppBar)
                    Text(
                      resolvedListingTitle,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          if (propertyId.isNotEmpty)
            _ConversationPropertyBanner(
              propertyId: propertyId,
              property: propertyModel,
              fallbackTitle: convPropertyTitle,
            ),
          // ── Message list with read receipts ───────────────────────────
          Expanded(
            child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: _convRef.snapshots(),
              builder: (context, convSnap) {
                DateTime? peerLastReadAt;
                if (convSnap.hasData && convSnap.data!.exists) {
                  final data = convSnap.data!.data() ?? {};
                  final readMap = data['lastReadAtByUser'];
                  if (readMap is Map) {
                    // Find the peer's last read (any key that isn't currentUserId)
                    for (final entry in readMap.entries) {
                      if (entry.key != widget.currentUserId) {
                        final ts = entry.value;
                        if (ts is Timestamp) {
                          peerLastReadAt = ts.toDate();
                        }
                      }
                    }
                  }
                }
                return _MessageList(
                  messagesRef: _messagesRef,
                  currentUserId: widget.currentUserId,
                  scrollController: _scrollController,
                  pending: List.unmodifiable(_pending),
                  peerIsTyping: _peerIsTyping,
                  peerLastReadAt: peerLastReadAt,
                  onNewMessages: _scrollToBottom,
                  onDeleteMessage: _deleteMessage,
                );
              },
            ),
          ),
          // ── Input bar ──────────────────────────────────────────────────
          const Divider(height: 1),
          _MessageInput(
            controller: _inputController,
            sending: _sending,
            onSend: _send,
            onPickImage: _pickImage,
            onTemplates: () => showMessageTemplatesSheet(
              context,
              onSelected: _insertTemplate,
            ),
            onShareProperty: () => _showPropertyPicker(context),
          ),
        ],
      ),
    );
  }
}

/// Listing strip under the app bar — same role as iOS `PropertyContextHeader`.
class _ConversationPropertyBanner extends StatelessWidget {
  const _ConversationPropertyBanner({
    required this.propertyId,
    required this.property,
    required this.fallbackTitle,
  });

  final String propertyId;
  final PropertyModel? property;
  final String fallbackTitle;

  String? get _imageUrl {
    if (property == null) return null;
    final h = property!.heroImageUrl?.trim();
    if (h != null && h.isNotEmpty) return h;
    if (property!.imageUrls.isNotEmpty) return property!.imageUrls.first;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final title = property?.title ?? fallbackTitle;
    final hasId = propertyId.isNotEmpty;

    if (hasId && property == null && title.trim().isEmpty) {
      return Material(
        color: AppColors.surfaceVariant,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              SizedBox(
                width: 56,
                height: 56,
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Loading listing…',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
            ],
          ),
        ),
      );
    }

    if (title.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    final subtitle = property?.locationLine ?? '';
    final price = property?.displayPriceWithCurrencyCode ?? '';

    return Material(
      color: AppColors.surfaceVariant,
      child: InkWell(
        onTap: () => context.push('/property/$propertyId'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: _imageUrl != null
                    ? CachedNetworkImage(
                        imageUrl: _imageUrl!,
                        width: 56,
                        height: 56,
                        fit: BoxFit.cover,
                        memCacheWidth: 112,
                        memCacheHeight: 112,
                        placeholder: (_, __) => Container(
                          width: 56,
                          height: 56,
                          color: AppColors.surface,
                          child: const Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        ),
                        errorWidget: (_, __, ___) => _placeholderThumb(),
                      )
                    : _placeholderThumb(),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (price.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        price,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _placeholderThumb() {
    return Container(
      width: 56,
      height: 56,
      color: AppColors.surface,
      child: const Icon(
        Icons.home_outlined,
        color: AppColors.textTertiary,
        size: 28,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Message list
// ─────────────────────────────────────────────────────────────────────────────

class _MessageList extends StatelessWidget {
  const _MessageList({
    required this.messagesRef,
    required this.currentUserId,
    required this.scrollController,
    required this.pending,
    required this.peerIsTyping,
    required this.onNewMessages,
    required this.onDeleteMessage,
    this.peerLastReadAt,
  });

  final CollectionReference<Map<String, dynamic>> messagesRef;
  final String currentUserId;
  final ScrollController scrollController;
  final List<_PendingMsg> pending;
  final bool peerIsTyping;
  final DateTime? peerLastReadAt;
  final VoidCallback onNewMessages;
  final Future<void> Function(String docId) onDeleteMessage;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: messagesRef.orderBy('createdAt').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _MessageListFallback(
            messagesRef: messagesRef,
            currentUserId: currentUserId,
            scrollController: scrollController,
            pending: pending,
            peerIsTyping: peerIsTyping,
            onNewMessages: onNewMessages,
            onDeleteMessage: onDeleteMessage,
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!.docs;
        final items = _buildItems(docs, pending, currentUserId);
        if (items.isEmpty) return const _EmptyChat();
        WidgetsBinding.instance.addPostFrameCallback((_) => onNewMessages());
        return _buildListView(context, items);
      },
    );
  }

  Widget _buildListView(BuildContext context, List<_Item> items) {
    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      // Extra item for typing indicator
      itemCount: items.length + (peerIsTyping ? 1 : 0),
      itemBuilder: (context, i) {
        // Typing indicator as last item
        if (peerIsTyping && i == items.length) {
          return const _TypingBubble();
        }
        final item = items[i];
        final isMe = item.senderId == currentUserId;
        // Show "Read" receipt on the last message I sent that the peer has read
        final isLastSentByMe = isMe &&
            !items
                .skip(i + 1)
                .any((m) => m.senderId == currentUserId);
        final isRead = isLastSentByMe &&
            peerLastReadAt != null &&
            item.createdAt != null &&
            !item.createdAt!.isAfter(peerLastReadAt!);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (item.showDateSeparator) _DateSeparator(label: _dateHeader(item.createdAt)),
            _MessageBubble(
              item: item,
              isMe: isMe,
              showReadReceipt: isRead,
              currentUserId: currentUserId,
              messagesRef: messagesRef,
              onDelete: (item.docId != null && isMe)
                  ? () => onDeleteMessage(item.docId!)
                  : null,
              onImageTap: item.imageUrl != null
                  ? () => FullScreenImageGallery.open(
                        context,
                        [item.imageUrl!],
                        0,
                      )
                  : null,
            ),
            // Property badge — mirrors iOS PropertyBadge component
            if (item.messagePropertyId != null &&
                item.messagePropertyId!.isNotEmpty)
              Padding(
                padding: EdgeInsets.only(
                  left: isMe ? 48 : 8,
                  right: isMe ? 8 : 48,
                  bottom: 4,
                ),
                child: Align(
                  alignment: isMe
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: _PropertyBadge(
                    propertyId: item.messagePropertyId!,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Fallback: no orderBy (missing index) — sort client-side.
class _MessageListFallback extends StatelessWidget {
  const _MessageListFallback({
    required this.messagesRef,
    required this.currentUserId,
    required this.scrollController,
    required this.pending,
    required this.peerIsTyping,
    required this.onNewMessages,
    required this.onDeleteMessage,
  });

  final CollectionReference<Map<String, dynamic>> messagesRef;
  final String currentUserId;
  final ScrollController scrollController;
  final List<_PendingMsg> pending;
  final bool peerIsTyping;
  final VoidCallback onNewMessages;
  final Future<void> Function(String docId) onDeleteMessage;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: messagesRef.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final sorted = snapshot.data!.docs.toList()
          ..sort((a, b) {
            final aTs = a.data()['createdAt'];
            final bTs = b.data()['createdAt'];
            if (aTs is Timestamp && bTs is Timestamp) return aTs.compareTo(bTs);
            return 0;
          });
        final items = _buildItems(sorted, pending, currentUserId);
        if (items.isEmpty) return const _EmptyChat();
        WidgetsBinding.instance.addPostFrameCallback((_) => onNewMessages());
        return _MessageList(
          messagesRef: messagesRef,
          currentUserId: currentUserId,
          scrollController: scrollController,
          pending: pending,
          peerIsTyping: peerIsTyping,
          onNewMessages: onNewMessages,
          onDeleteMessage: onDeleteMessage,
        )._buildListView(context, items);
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Date separator
// ─────────────────────────────────────────────────────────────────────────────

class _DateSeparator extends StatelessWidget {
  const _DateSeparator({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(child: Divider(color: Colors.grey.shade300, height: 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: AppColors.textTertiary,
                letterSpacing: 0.3,
              ),
            ),
          ),
          Expanded(child: Divider(color: Colors.grey.shade300, height: 1)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Message bubble
// ─────────────────────────────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.item,
    required this.isMe,
    this.showReadReceipt = false,
    this.onDelete,
    this.onImageTap,
    this.currentUserId,
    this.messagesRef,
  });

  final _Item item;
  final bool isMe;
  final bool showReadReceipt;
  final VoidCallback? onDelete;
  final VoidCallback? onImageTap;
  final String? currentUserId;
  final CollectionReference<Map<String, dynamic>>? messagesRef;

  static const _reactionEmojis = ['👍', '❤️', '🏠', '🔑', '😮', '😂'];

  Map<String, int> get _reactionCounts {
    final raw = item.data?['reactions'];
    if (raw is! Map) return {};
    final counts = <String, int>{};
    for (final v in raw.values) {
      if (v is String) counts[v] = (counts[v] ?? 0) + 1;
    }
    return counts;
  }

  String? get _myReaction {
    final raw = item.data?['reactions'];
    if (raw is! Map || currentUserId == null) return null;
    return raw[currentUserId] as String?;
  }

  Future<void> _toggleReaction(String emoji) async {
    if (item.docId == null || messagesRef == null || currentUserId == null) return;
    final current = _myReaction;
    final ref = messagesRef!.doc(item.docId);
    if (current == emoji) {
      // Remove reaction
      await ref.update({'reactions.$currentUserId': FieldValue.delete()});
    } else {
      // Set reaction
      await ref.update({'reactions.$currentUserId': emoji});
    }
  }

  void _showReactionPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.12),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: _reactionEmojis.map((e) {
                final isSelected = _myReaction == e;
                return GestureDetector(
                  onTap: () {
                    Navigator.of(context).pop();
                    _toggleReaction(e);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primary.withOpacity(0.15)
                          : Colors.transparent,
                      shape: BoxShape.circle,
                    ),
                    child: Text(e, style: const TextStyle(fontSize: 28)),
                  ),
                );
              }).toList(),
            ),
            if (onDelete != null) ...[
              const Divider(height: 20),
              ListTile(
                leading: const Icon(Icons.delete_outline,
                    color: AppColors.error, size: 20),
                title: const Text('Delete message',
                    style: TextStyle(color: AppColors.error)),
                contentPadding: EdgeInsets.zero,
                onTap: () {
                  Navigator.of(context).pop();
                  onDelete!();
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pending = item.pending;
    final isFailed = pending?.failed ?? false;
    final reactionCounts = _reactionCounts;

    return Column(
      crossAxisAlignment:
          isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Align(
          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: GestureDetector(
            onLongPress: () => _showReactionPicker(context),
            child: Container(
              margin: EdgeInsets.only(
                bottom: showReadReceipt ? 2 : (item.isLastInGroup ? 8 : 2),
                left: isMe ? 48 : 0,
                right: isMe ? 0 : 48,
              ),
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.72,
              ),
              decoration: BoxDecoration(
                color: isMe
                    ? (isFailed ? AppColors.error : AppColors.primary)
                    : AppColors.surfaceVariant,
                borderRadius: _bubbleRadius(),
              ),
              child: item.isImage
                  ? _buildImageContent(context)
                  : _buildTextContent(),
            ),
          ),
        ),
        // Reaction pills strip — mirrors iMessage tapback display
        if (reactionCounts.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(
              left: isMe ? 48 : 4,
              right: isMe ? 4 : 48,
              top: 2,
              bottom: 2,
            ),
            child: Wrap(
              spacing: 4,
              children: reactionCounts.entries.map((e) {
                final isMyReaction = _myReaction == e.key;
                return GestureDetector(
                  onTap: () => _toggleReaction(e.key),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: isMyReaction
                          ? AppColors.primary.withOpacity(0.15)
                          : AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(12),
                      border: isMyReaction
                          ? Border.all(
                              color: AppColors.primary.withOpacity(0.4))
                          : null,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(e.key,
                            style: const TextStyle(fontSize: 14)),
                        if (e.value > 1) ...[
                          const SizedBox(width: 3),
                          Text(
                            '${e.value}',
                            style: TextStyle(
                              fontSize: 12,
                              color: isMyReaction
                                  ? AppColors.primary
                                  : AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        // Read receipt — "Read" label with checkmarks
        if (showReadReceipt)
          Padding(
            padding: EdgeInsets.only(
              right: isMe ? 4 : 0,
              left: isMe ? 0 : 4,
              bottom: item.isLastInGroup ? 8 : 4,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.done_all,
                    size: 13, color: AppColors.primary),
                SizedBox(width: 3),
                Text(
                  'Read',
                  style: TextStyle(
                      fontSize: 11,
                      color: AppColors.primary,
                      fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
      ],
    );
  }

  BorderRadius _bubbleRadius() {
    // Own messages: tail is bottom-right (small radius)
    // Peer messages: tail is bottom-left (small radius)
    const large = Radius.circular(16);
    const small = Radius.circular(4);
    const mid = Radius.circular(6);

    if (isMe) {
      return BorderRadius.only(
        topLeft: large,
        topRight: item.isFirstInGroup ? large : mid,
        bottomRight: item.isLastInGroup ? small : mid,
        bottomLeft: large,
      );
    } else {
      return BorderRadius.only(
        topLeft: item.isFirstInGroup ? large : mid,
        topRight: large,
        bottomLeft: item.isLastInGroup ? small : mid,
        bottomRight: large,
      );
    }
  }

  Widget _buildTextContent() {
    final dt = item.createdAt;
    final pending = item.pending;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            item.text,
            style: TextStyle(
              color: isMe ? Colors.white : AppColors.textPrimary,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                DateFormat.jm().format(dt),
                style: TextStyle(
                  fontSize: 10,
                  color: isMe
                      ? Colors.white.withValues(alpha: 0.7)
                      : AppColors.textTertiary,
                ),
              ),
              if (pending != null) ...[
                const SizedBox(width: 4),
                if (pending.failed)
                  Icon(Icons.error_outline_rounded,
                      size: 12, color: Colors.white.withValues(alpha: 0.85))
                else
                  SizedBox(
                    width: 10,
                    height: 10,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
              ] else if (isMe) ...[
                const SizedBox(width: 4),
                Icon(
                  Icons.done_all_rounded,
                  size: 13,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildImageContent(BuildContext context) {
    final pending = item.pending;

    Widget imageWidget;
    if (pending?.localImageFile != null) {
      imageWidget = Image.file(
        pending!.localImageFile!,
        fit: BoxFit.cover,
        width: 220,
        height: 180,
      );
    } else if (item.imageUrl != null) {
      imageWidget = CachedNetworkImage(
        imageUrl: item.imageUrl!,
        fit: BoxFit.cover,
        width: 220,
        height: 180,
        memCacheWidth: 440,
        memCacheHeight: 360,
        placeholder: (_, __) => Container(
          width: 220,
          height: 180,
          color: Colors.black12,
          child: const Center(child: CircularProgressIndicator()),
        ),
        errorWidget: (_, __, ___) => Container(
          width: 220,
          height: 180,
          color: Colors.black12,
          child: const Icon(Icons.broken_image_outlined),
        ),
      );
    } else {
      imageWidget = Container(
        width: 220,
        height: 180,
        color: Colors.black12,
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    return ClipRRect(
      borderRadius: _bubbleRadius(),
      child: Stack(
        children: [
          GestureDetector(
            onTap: onImageTap,
            child: imageWidget,
          ),
          // Upload progress overlay
          if (pending != null && !pending.failed && pending.uploadProgress < 1.0)
            Positioned.fill(
              child: Container(
                color: Colors.black38,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(
                        value: pending.uploadProgress > 0
                            ? pending.uploadProgress
                            : null,
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                      if (pending.uploadProgress > 0) ...[
                        const SizedBox(height: 6),
                        Text(
                          '${(pending.uploadProgress * 100).round()}%',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          // Failed overlay
          if (pending?.failed == true)
            Positioned.fill(
              child: Container(
                color: Colors.black45,
                child: const Center(
                  child: Icon(Icons.error_outline_rounded,
                      color: Colors.white, size: 32),
                ),
              ),
            ),
          // Timestamp chip
          Positioned(
            bottom: 6,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black45,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                DateFormat.jm().format(item.createdAt),
                style: const TextStyle(color: Colors.white, fontSize: 10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showDeleteMenu(BuildContext context) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded,
                  color: AppColors.error),
              title: const Text(
                'Delete message',
                style: TextStyle(color: AppColors.error),
              ),
              onTap: () {
                Navigator.pop(ctx);
                onDelete?.call();
              },
            ),
            ListTile(
              leading: const Icon(Icons.close_rounded),
              title: const Text('Cancel'),
              onTap: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Typing indicator bubble (iOS TypingIndicatorView parity)
// ─────────────────────────────────────────────────────────────────────────────

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(16),
          ),
        ),
        child: const _AnimatedDots(),
      ),
    );
  }
}

class _AnimatedDots extends StatefulWidget {
  const _AnimatedDots();

  @override
  State<_AnimatedDots> createState() => _AnimatedDotsState();
}

class _AnimatedDotsState extends State<_AnimatedDots>
    with TickerProviderStateMixin {
  late final List<AnimationController> _controllers;
  late final List<Animation<double>> _anims;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(
      3,
      (i) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 550),
      ),
    );
    _anims = _controllers
        .map((c) => Tween<double>(begin: 0, end: -5).animate(
              CurvedAnimation(parent: c, curve: Curves.easeInOut),
            ))
        .toList();
    for (var i = 0; i < 3; i++) {
      Future.delayed(Duration(milliseconds: i * 180), () {
        if (mounted) _controllers[i].repeat(reverse: true);
      });
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        return AnimatedBuilder(
          animation: _anims[i],
          builder: (_, __) => Transform.translate(
            offset: Offset(0, _anims[i].value),
            child: Container(
              width: 7,
              height: 7,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        );
      }),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty chat
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyChat extends StatelessWidget {
  const _EmptyChat();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'No messages yet.\nSay hello! 👋',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.textSecondary, fontSize: 15),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Peer avatar
// ─────────────────────────────────────────────────────────────────────────────

class _PeerAvatar extends StatelessWidget {
  const _PeerAvatar({required this.name, this.photoUrl, this.radius = 20});

  final String name;
  final String? photoUrl;
  final double radius;

  @override
  Widget build(BuildContext context) {
    if (photoUrl != null && photoUrl!.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: AppColors.surfaceVariant,
        backgroundImage: CachedNetworkImageProvider(photoUrl!),
      );
    }
    final initials = name.trim().isEmpty
        ? '?'
        : name.trim().split(' ').map((s) => s[0]).take(2).join().toUpperCase();
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.primary.withValues(alpha: 0.15),
      child: Text(
        initials,
        style: TextStyle(
          color: AppColors.primary,
          fontWeight: FontWeight.w700,
          fontSize: radius * 0.65,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Message input bar
// ─────────────────────────────────────────────────────────────────────────────

class _MessageInput extends StatelessWidget {
  const _MessageInput({
    required this.controller,
    required this.sending,
    required this.onSend,
    required this.onPickImage,
    required this.onTemplates,
    this.onShareProperty,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;
  final VoidCallback onPickImage;
  final VoidCallback onTemplates;
  /// Share a property card in the conversation — mirrors iOS house icon button
  final VoidCallback? onShareProperty;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Templates
            IconButton(
              tooltip: 'Templates',
              onPressed: sending ? null : onTemplates,
              icon: const Icon(Icons.article_outlined),
              color: AppColors.primary,
            ),
            // Image picker (matches iOS photo picker button)
            IconButton(
              tooltip: 'Send photo',
              onPressed: sending ? null : onPickImage,
              icon: const Icon(Icons.photo_outlined),
              color: AppColors.primary,
            ),
            // Share property — mirrors iOS house button in ChatView toolbar
            if (onShareProperty != null)
              IconButton(
                tooltip: 'Share property',
                onPressed: sending ? null : onShareProperty,
                icon: const Icon(Icons.home_outlined),
                color: AppColors.primary,
              ),
            // Text field
            Expanded(
              child: TextField(
                controller: controller,
                textCapitalization: TextCapitalization.sentences,
                maxLines: null,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: 'Type a message…',
                  filled: true,
                  fillColor: AppColors.surfaceVariant,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Send button
            IconButton.filled(
              onPressed: sending ? null : onSend,
              icon: sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send_rounded),
              style: IconButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Property Badge ───────────────────────────────────────────────────────────
// Mirrors iOS PropertyBadge — house icon + property title pill shown below a
// message bubble when message.propertyId is set.

class _PropertyBadge extends StatefulWidget {
  const _PropertyBadge({required this.propertyId});
  final String propertyId;

  @override
  State<_PropertyBadge> createState() => _PropertyBadgeState();
}

class _PropertyBadgeState extends State<_PropertyBadge> {
  String? _title;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('properties')
          .doc(widget.propertyId)
          .get();
      if (!mounted) return;
      setState(() => _title = snap.data()?['title'] as String? ?? 'Property');
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/property/${widget.propertyId}'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.primary.withOpacity(0.10),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.home, size: 12, color: AppColors.primary),
            const SizedBox(width: 4),
            Text(
              _title ?? 'Property',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.primary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Property Picker for Chat ─────────────────────────────────────────────────

class _PropertyPickerForChat extends StatefulWidget {
  const _PropertyPickerForChat({required this.onSelected});
  final void Function(String propertyId, String propertyTitle) onSelected;

  @override
  State<_PropertyPickerForChat> createState() => _PropertyPickerForChatState();
}

class _PropertyPickerForChatState extends State<_PropertyPickerForChat> {
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('properties')
          .where('deleted', isEqualTo: false)
          .limit(50)
          .get();
      if (!mounted) return;
      setState(() {
        _results = snap.docs.map((d) {
          final m = d.data();
          return {
            'id': d.id,
            'title': m['title'] as String? ?? 'Property',
            'city': m['city'] as String? ?? '',
            'heroImageUrl': m['heroImageUrl'] as String?,
          };
        }).toList();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _searchCtrl.text.toLowerCase().trim();
    if (q.isEmpty) return _results;
    return _results.where((p) {
      return (p['title'] as String).toLowerCase().contains(q) ||
          (p['city'] as String).toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 8),
        Center(
          child: Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              const Text('Share a Property',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _searchCtrl,
            decoration: const InputDecoration(
              hintText: 'Search properties…',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _filtered.isEmpty
                  ? Center(
                      child: Text('No properties found',
                          style: TextStyle(color: AppColors.textSecondary)),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _filtered.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (ctx, i) {
                        final p = _filtered[i];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: p['heroImageUrl'] != null
                                ? CachedNetworkImage(
                                    imageUrl: p['heroImageUrl'] as String,
                                    width: 48, height: 48, fit: BoxFit.cover,
                                  )
                                : Container(
                                    width: 48, height: 48,
                                    color: AppColors.surfaceVariant,
                                    child: const Icon(Icons.home,
                                        color: AppColors.textSecondary),
                                  ),
                          ),
                          title: Text(p['title'] as String,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(p['city'] as String,
                              style: TextStyle(
                                  fontSize: 12, color: AppColors.textSecondary)),
                          trailing: Icon(Icons.share_outlined,
                              color: AppColors.primary),
                          onTap: () => widget.onSelected(
                              p['id'] as String, p['title'] as String),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

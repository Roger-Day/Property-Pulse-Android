import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../models/ai_listing_draft.dart';
import '../models/ai_listing_suggestion.dart';
import '../services/ai/ai_exceptions.dart';
import '../services/ai/ai_listing_service.dart';
import 'pp_widgets.dart';

/// Shows the AI listing-description review sheet and returns the accepted
/// [AiListingSuggestion], or `null` if the user dismissed it, cancelled, or
/// chose "Edit manually" without accepting anything.
///
/// The description is ALWAYS just returned here — this function and the
/// sheet never touch [PropertyRepository] or Firestore. The caller (an
/// add/edit-listing screen) decides what to do with the result, typically
/// filling its own description controller:
///
/// ```dart
/// final suggestion = await showAiListingSuggestionSheet(
///   context: context,
///   service: context.read<AiListingService>(),
///   getDraft: () => AiListingDraft(propertyType: ..., bedrooms: ...),
///   propertyId: widget.propertyId, // null while still creating a listing
/// );
/// if (suggestion != null) {
///   setState(() => _descCtrl.text = suggestion.description);
/// }
/// ```
///
/// Tone and regeneration are owned entirely by this sheet, not by
/// [getDraft] — the caller's draft is just the base property facts. The
/// sheet layers a selected [AiListingTone] and a regeneration-attempt
/// counter on top via [AiListingDraft.withToneAndAttempt] before each
/// generate call, so add/edit-listing screens never need to know either
/// concept exists.
Future<AiListingSuggestion?> showAiListingSuggestionSheet({
  required BuildContext context,
  required AiListingService service,
  required AiListingDraft Function() getDraft,
  String? propertyId,
}) {
  return showModalBottomSheet<AiListingSuggestion>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    isDismissible: true,
    builder: (_) => _AiListingSuggestionSheetBody(
      service: service,
      getDraft: getDraft,
      propertyId: propertyId,
    ),
  );
}

enum _Phase { loading, loaded, error }

class _AiListingSuggestionSheetBody extends StatefulWidget {
  const _AiListingSuggestionSheetBody({
    required this.service,
    required this.getDraft,
    required this.propertyId,
  });

  final AiListingService service;
  final AiListingDraft Function() getDraft;
  final String? propertyId;

  @override
  State<_AiListingSuggestionSheetBody> createState() => _AiListingSuggestionSheetBodyState();
}

class _AiListingSuggestionSheetBodyState extends State<_AiListingSuggestionSheetBody> {
  _Phase _phase = _Phase.loading;
  AiListingSuggestion? _suggestion;
  String? _errorMessage;

  // Null means "let the backend pick a category-appropriate default" (see
  // defaultToneForCategory in ai-listing-validation.js) — only set once the
  // user explicitly taps a tone chip.
  AiListingTone? _selectedTone;

  // How many times "Regenerate" has been tapped for the CURRENT tone/facts.
  // Reset to 0 whenever the tone changes, since a tone change is already a
  // different prompt — it doesn't need the variation nudge too. Threaded
  // into the draft so the backend both busts its cache and asks the model
  // for a genuinely different piece, not the same cached result again (see
  // AiListingDraft.regenerationAttempt's doc comment).
  int _regenerationAttempt = 0;

  // Dart Futures can't be cancelled mid-flight — "Cancel" means "stop
  // waiting on this and never apply its result", not "abort the network
  // call". This flag is what makes a stale response a no-op.
  bool _cancelled = false;

  // The description is an editable starting point, not applied verbatim —
  // this controller holds the user's own edits on top of whatever the
  // model generated. Reset to the fresh AI text every time a new
  // generation lands (initial load, tone change, regenerate), so a new
  // draft never shows stale edits from a previous one.
  final _descriptionController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _generate();
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    if (!mounted) return;
    setState(() {
      _phase = _Phase.loading;
      _errorMessage = null;
    });

    final draft = widget.getDraft().withToneAndAttempt(
          tone: _selectedTone,
          regenerationAttempt: _regenerationAttempt,
        );
    if (!draft.hasAnyFact) {
      if (!mounted || _cancelled) return;
      setState(() {
        _phase = _Phase.error;
        _errorMessage = 'Enter at least a property type or a few details first.';
      });
      return;
    }

    try {
      final result = await widget.service.generateDescription(
        propertyId: widget.propertyId,
        draft: draft,
      );
      if (!mounted || _cancelled) return;
      PPHaptics.success();
      _descriptionController.text = result.description;
      setState(() {
        _phase = _Phase.loaded;
        _suggestion = result;
      });
    } on AiException catch (e) {
      if (!mounted || _cancelled) return;
      PPHaptics.error();
      setState(() {
        _phase = _Phase.error;
        _errorMessage = e.userMessage;
      });
    } catch (_) {
      // AiGateway wraps everything it can into AiException, but response
      // parsing (or anything unforeseen) must still land in the sheet's
      // error state, never escape to the zone handler mid-flow.
      if (!mounted || _cancelled) return;
      PPHaptics.error();
      setState(() {
        _phase = _Phase.error;
        _errorMessage = 'Something went wrong. Please try again.';
      });
    }
  }

  Future<void> _regenerate() async {
    _regenerationAttempt++;
    await _generate();
  }

  Future<void> _selectTone(AiListingTone tone) async {
    if (tone == _selectedTone) return;
    _selectedTone = tone;
    _regenerationAttempt = 0;
    await _generate();
  }

  void _cancel() {
    _cancelled = true;
    Navigator.of(context).pop();
  }

  void _accept() {
    final edited = _suggestion!.copyWith(
      description: _descriptionController.text.trim(),
    );
    Navigator.of(context).pop(edited);
  }

  void _editManually() {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(left: 20, right: 20, bottom: bottomInset + 20, top: 4),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'AI description',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'A starting point based on what you\'ve entered — review and edit before using it.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
            ),
            const SizedBox(height: 20),
            switch (_phase) {
              _Phase.loading => _LoadingSection(onCancel: _cancel),
              _Phase.error => _ErrorSection(
                  message: _errorMessage ?? 'Something went wrong. Please try again.',
                  onRetry: _generate,
                  onClose: _editManually,
                ),
              _Phase.loaded => _LoadedSection(
                  suggestion: _suggestion!,
                  descriptionController: _descriptionController,
                  selectedTone: _selectedTone,
                  onToneSelected: _selectTone,
                  onAccept: _accept,
                  onRegenerate: _regenerate,
                  onEditManually: _editManually,
                ),
            },
          ],
        ),
      ),
    );
  }
}

class _LoadingSection extends StatelessWidget {
  const _LoadingSection({required this.onCancel});
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(
          height: 140,
          child: PPLoadingView(message: 'Writing your description…'),
        ),
        const SizedBox(height: 12),
        PPOutlinedButton(label: 'Cancel', onPressed: onCancel),
      ],
    );
  }
}

class _ErrorSection extends StatelessWidget {
  const _ErrorSection({
    required this.message,
    required this.onRetry,
    required this.onClose,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PPCard(
          color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.3),
          child: Row(
            children: [
              Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
              const SizedBox(width: 12),
              Expanded(child: Text(message, style: Theme.of(context).textTheme.bodyMedium)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        PPFilledButton(label: 'Try again', onPressed: onRetry),
        const SizedBox(height: 8),
        PPOutlinedButton(label: 'Close', onPressed: onClose),
      ],
    );
  }
}

class _LoadedSection extends StatelessWidget {
  const _LoadedSection({
    required this.suggestion,
    required this.descriptionController,
    required this.selectedTone,
    required this.onToneSelected,
    required this.onAccept,
    required this.onRegenerate,
    required this.onEditManually,
  });

  final AiListingSuggestion suggestion;
  final TextEditingController descriptionController;
  final AiListingTone? selectedTone;
  final ValueChanged<AiListingTone> onToneSelected;
  final VoidCallback onAccept;
  final VoidCallback onRegenerate;
  final VoidCallback onEditManually;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Tone',
          style: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: AiListingTone.values.map((tone) {
            final isSelected = tone == selectedTone;
            return ChoiceChip(
              label: Text(tone.displayLabel),
              selected: isSelected,
              selectedColor: AppColors.primary,
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : AppColors.textPrimary,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              ),
              onSelected: (_) => onToneSelected(tone),
            );
          }).toList(),
        ),
        const SizedBox(height: 18),
        Text(
          suggestion.headline,
          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: descriptionController,
          maxLines: null,
          minLines: 4,
          style: textTheme.bodyMedium,
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.all(12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
            ),
          ),
        ),
        if (suggestion.callToAction.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            suggestion.callToAction,
            style: textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
        ],
        if (suggestion.envelope.cacheHit) ...[
          const SizedBox(height: 10),
          Text(
            'Showing a previously generated result for these details.',
            style: textTheme.bodySmall?.copyWith(color: Colors.grey[600], fontStyle: FontStyle.italic),
          ),
        ],
        const SizedBox(height: 20),
        PPFilledButton(label: 'Use this description', onPressed: onAccept, icon: Icons.check),
        const SizedBox(height: 8),
        PPOutlinedButton(label: 'Regenerate', onPressed: onRegenerate, icon: Icons.refresh),
        const SizedBox(height: 8),
        PPOutlinedButton(label: 'Edit manually instead', onPressed: onEditManually),
      ],
    );
  }
}

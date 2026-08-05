import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../constants/app_colors.dart';
import '../../../models/ai_capability.dart';
import '../../../providers/ai_feature_flags_provider.dart';
import '../../../services/search/pending_search_handoff.dart';
import '../../../widgets/pp_widgets.dart';
import '../../../widgets/project_listing_card.dart';
import '../controllers/pulse_finder_conversation_controller.dart';
import '../widgets/pulse_finder_message_bubble.dart';
import '../widgets/pulse_finder_prompt_cards.dart';
import '../widgets/pulse_finder_quick_replies.dart';
import '../widgets/pulse_finder_result_card.dart';
import '../widgets/pulse_finder_summary_card.dart';
import '../widgets/pulse_finder_typing_indicator.dart';

/// Pulse Finder (Phase 3) — the dedicated conversational property-discovery
/// screen. A single route (`/pulse-finder`) switches between an intro view
/// (suggested prompts) and a chat view (messages + results) by the
/// route-scoped `PulseFinderConversationController`'s phase — not two
/// separate routes, so there is exactly one back-stack entry for the whole
/// experience.
class PulseFinderScreen extends StatefulWidget {
  const PulseFinderScreen({super.key, this.resumeSessionId});

  /// Phase 4 — when set (via `/pulse-finder?sessionId=…` from the history
  /// screen), the saved consultation is reopened and continued instead of
  /// starting a fresh one.
  final String? resumeSessionId;

  @override
  State<PulseFinderScreen> createState() => _PulseFinderScreenState();
}

class _PulseFinderScreenState extends State<PulseFinderScreen> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final controller = context.read<PulseFinderConversationController>();
      controller.logOpened();
      final resumeId = widget.resumeSessionId;
      if (resumeId != null && resumeId.isNotEmpty) {
        controller.resume(resumeId);
      }
    });
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  void _send() {
    final text = _inputController.text;
    if (text.trim().isEmpty) return;
    _inputController.clear();
    context.read<PulseFinderConversationController>().sendMessage(text);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = context.watch<AiFeatureFlagsProvider>().isEnabled(AiCapability.propertyChat);

    final phase = context.watch<PulseFinderConversationController>().phase;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pulse Finder'),
        backgroundColor: AppColors.surface,
        elevation: 0,
        actions: [
          if (enabled)
            IconButton(
              tooltip: 'Your consultations',
              icon: const Icon(Icons.history),
              onPressed: () => context.push('/pulse-finder/history'),
            ),
          if (enabled && phase != PulseFinderPhase.intro)
            IconButton(
              tooltip: 'New search',
              icon: const Icon(Icons.refresh),
              onPressed: () => context.read<PulseFinderConversationController>().startOver(),
            ),
        ],
      ),
      body: SafeArea(
        child: enabled ? _buildBody(context) : const _PulseFinderUnavailable(),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final controller = context.watch<PulseFinderConversationController>();

    if (controller.phase == PulseFinderPhase.intro) {
      return _PulseFinderIntro(
        inputController: _inputController,
        onSelectPrompt: (prompt) => context.read<PulseFinderConversationController>().sendMessage(prompt),
        onSubmitCustom: _send,
      );
    }

    if (controller.phase == PulseFinderPhase.results) {
      controller.resultsViewed();
    }
    _scrollToBottom();

    return Column(
      children: [
        Expanded(
          child: ListView(
            controller: _scrollController,
            padding: const EdgeInsets.all(16),
            children: [
              for (final message in controller.messages)
                PulseFinderMessageBubble(message: message),
              if (controller.isWaitingForReply) const PulseFinderTypingIndicator(),
              if (controller.phase == PulseFinderPhase.error && controller.errorMessage != null)
                _PulseFinderErrorBanner(
                  message: controller.errorMessage!,
                  onRetry: () => context.read<PulseFinderConversationController>().retry(),
                ),
              if (controller.phase == PulseFinderPhase.results) ..._buildResultsSection(context, controller),
            ],
          ),
        ),
        if (controller.phase == PulseFinderPhase.results && !controller.isSearching)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: PulseFinderQuickReplies(
              onSelected: (text) => context.read<PulseFinderConversationController>().sendMessage(text),
            ),
          ),
        _PulseFinderInputBar(controller: _inputController, onSend: _send, enabled: !controller.isBusy),
      ],
    );
  }

  List<Widget> _buildResultsSection(
    BuildContext context,
    PulseFinderConversationController controller,
  ) {
    if (controller.isSearching) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: PPLoadingView(message: 'Finding properties…'),
        ),
      ];
    }
    final filter = controller.currentFilter!;
    final developments = controller.developments;

    if (controller.results.isEmpty && developments.isEmpty) {
      final guidance = controller.emptyResultsGuidance();
      return [
        const SizedBox(height: 8),
        PulseFinderSummaryCard(
          filter: filter,
          expanded: controller.summaryExpanded,
          onToggleExpanded: () => controller.toggleSummaryExpanded(),
          onEditSearch: () => controller.editSummary(),
          onRunSearchAgain: () => controller.runSearchAgain(),
          intent: controller.profile.intent,
          propertyTypeRefinement: controller.profile.propertyTypeRefinement,
        ),
        const SizedBox(height: 12),
        PPEmptyState(
          icon: Icons.search_off,
          title: 'No matches yet',
          // Category-specific — a short-stay or commercial search never
          // queries developments, so the old generic "properties or
          // developments" line was wrong for them. See
          // PulseFinderIntent.noMatchesMessage.
          message: controller.profile.intent?.noMatchesMessage ??
              'I couldn\'t find any listings matching every requirement. Here\'s what might help:',
        ),
        for (final tip in guidance)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.lightbulb_outline, size: 16, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(child: Text(tip, style: Theme.of(context).textTheme.bodySmall)),
              ],
            ),
          ),
      ];
    }

    final recommendations = controller.recommendations;
    final hasMore = controller.results.length > recommendations.length;

    return [
      const SizedBox(height: 8),
      PulseFinderSummaryCard(
        filter: filter,
        expanded: controller.summaryExpanded,
        onToggleExpanded: () => controller.toggleSummaryExpanded(),
        onEditSearch: () => controller.editSummary(),
        onRunSearchAgain: () => controller.runSearchAgain(),
      ),
      if (developments.isNotEmpty) ...[
        const SizedBox(height: 14),
        Text(
          developments.length == 1 ? 'Matching development' : 'Matching developments',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        for (final development in developments)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: ProjectListingCard(
              project: development,
              onTap: () {
                controller.openDevelopment(development);
                context.push('/development/${development.firestoreDocumentId}');
              },
            ),
          ),
      ],
      if (recommendations.isNotEmpty) ...[
        const SizedBox(height: 14),
        Text(
          '${controller.results.length} ${controller.results.length == 1 ? 'match' : 'matches'} — '
          'here ${recommendations.length == 1 ? 'is my top pick' : 'are my top ${recommendations.length} picks'}',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
      ],
      for (final recommendation in recommendations)
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: PulseFinderResultCard(
            property: recommendation.property,
            reasons: recommendation.reasons,
            label: recommendation.label,
            onTap: () {
              controller.openProperty(recommendation.property);
              context.push('/property/${recommendation.property.id}');
            },
          ),
        ),
      if (hasMore)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: PPOutlinedButton(
            label: 'View All Matching Properties (${controller.results.length})',
            icon: Icons.grid_view_outlined,
            onPressed: () {
              controller.viewAllSelected();
              context.read<PendingSearchHandoff>().set(filter);
              context.go('/search');
            },
          ),
        ),
    ];
  }
}

class _PulseFinderIntro extends StatelessWidget {
  const _PulseFinderIntro({
    required this.inputController,
    required this.onSelectPrompt,
    required this.onSubmitCustom,
  });

  final TextEditingController inputController;
  final ValueChanged<String> onSelectPrompt;
  final VoidCallback onSubmitCustom;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Icon(Icons.auto_awesome, size: 40, color: AppColors.primary),
        const SizedBox(height: 12),
        Text(
          'Meet Pulse Finder',
          style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          'Tell me what you\'re looking for in plain language, and I\'ll ask a few '
          'quick questions to find the right properties for you — no filters to '
          'figure out yourself.',
          style: tt.bodyMedium?.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 24),
        Text('Get started with', style: tt.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        PulseFinderPromptCards(onSelected: onSelectPrompt),
        const SizedBox(height: 8),
        Text(
          'Or describe what you need below.',
          style: tt.bodySmall?.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 10),
        _PulseFinderInputBar(controller: inputController, onSend: onSubmitCustom, embedded: true),
      ],
    );
  }
}

class _PulseFinderInputBar extends StatelessWidget {
  const _PulseFinderInputBar({
    required this.controller,
    required this.onSend,
    this.embedded = false,
    this.enabled = true,
  });

  final TextEditingController controller;
  final VoidCallback onSend;

  /// True when placed inline on the intro screen (no elevated container),
  /// false when docked to the bottom of the chat view.
  final bool embedded;

  /// False while a turn/refinement/search is already in flight — disables
  /// the field and send button so a double-tap can't fire a second
  /// concurrent AI call for the same user action (the controller-level
  /// guard is `PulseFinderConversationController.isBusy`; this is its
  /// visible counterpart).
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final field = TextField(
      controller: controller,
      enabled: enabled,
      textInputAction: TextInputAction.send,
      onSubmitted: (_) => onSend(),
      minLines: 1,
      maxLines: 4,
      decoration: InputDecoration(
        hintText: 'Message Pulse Finder…',
        filled: true,
        fillColor: AppColors.surfaceVariant,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide.none,
        ),
      ),
    );

    final sendButton = IconButton.filled(
      tooltip: 'Send',
      style: IconButton.styleFrom(backgroundColor: AppColors.primary),
      icon: const Icon(Icons.arrow_upward, color: Colors.white, size: 20),
      onPressed: enabled ? onSend : null,
    );

    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(child: field),
        const SizedBox(width: 10),
        sendButton,
      ],
    );

    if (embedded) return row;

    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 10,
        bottom: 10 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, -2)),
        ],
      ),
      child: row,
    );
  }
}

class _PulseFinderErrorBanner extends StatelessWidget {
  const _PulseFinderErrorBanner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: PPCard(
        color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
                const SizedBox(width: 12),
                Expanded(child: Text(message, style: Theme.of(context).textTheme.bodyMedium)),
              ],
            ),
            const SizedBox(height: 12),
            PPOutlinedButton(label: 'Try again', onPressed: onRetry, icon: Icons.refresh),
          ],
        ),
      ),
    );
  }
}

class _PulseFinderUnavailable extends StatelessWidget {
  const _PulseFinderUnavailable();

  @override
  Widget build(BuildContext context) {
    return const PPEmptyState(
      icon: Icons.auto_awesome_outlined,
      title: 'Pulse Finder isn\'t available yet',
      message: 'This feature is rolling out soon. Check back shortly.',
    );
  }
}

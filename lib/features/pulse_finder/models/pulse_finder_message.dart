/// Pulse Finder (Phase 3) — a single chat turn.
///
/// Deliberately minimal: no persistence, no id beyond list order. Session
/// memory only — the whole list this belongs to lives on
/// `PulseFinderConversationController` and is discarded when that
/// controller is disposed (the `/pulse-finder` route popping).
enum PulseFinderRole { user, assistant }

class PulseFinderMessage {
  const PulseFinderMessage({
    required this.role,
    required this.text,
    required this.timestamp,
    this.isError = false,
  });

  final PulseFinderRole role;
  final String text;
  final DateTime timestamp;

  /// True for an assistant-role message that represents an inline error
  /// notice (e.g. "Something went wrong") rather than a real AI reply —
  /// lets the bubble widget style it distinctly without a separate model.
  final bool isError;
}

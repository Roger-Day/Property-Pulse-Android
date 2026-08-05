import '../../../models/property_model.dart';
import '../../../repositories/property_repository.dart';

/// Pulse Finder (Phase 3.1) — detects when a post-results message is a
/// genuine QUESTION about the current results ("Are there properties in
/// Mandeville?") rather than a refinement command ("show cheaper options"),
/// and answers it deterministically from the results the app already has.
///
/// Never routed to the AI: the propertyChat prompt template explicitly
/// tells the model it does not search, browse, or know about any actual
/// property listings (see functions/ai-prompt-templates.js) — it has no
/// visibility into the result set at all, so it could only ever guess or
/// invent an answer. A question doesn't change the search; it just reports
/// on it, using the same [PropertyFilter] the results were already
/// produced from.
class PulseFinderQuestionAnswerer {
  PulseFinderQuestionAnswerer._();

  static const List<String> _questionStarters = [
    'are there',
    'is there',
    'does',
    'do you',
    'can you',
    'how many',
    'what',
    'where',
    'which',
  ];

  /// "What about X?" / "how about X?" names a new consideration — a
  /// specific development, amenity, or place — rather than asking about
  /// the CURRENT results. Routing it as a question would silently ignore X
  /// and just re-report the existing (possibly empty) result set, which is
  /// exactly the bug this guards against: routed as a refinement instead,
  /// X flows into the deterministic parser and then the AI-search fallback
  /// like any other refinement text.
  static const List<String> _newConsiderationStarters = ['what about ', 'how about '];

  /// A simple heuristic, not real NLU — errs toward treating "are there
  /// X"/"is there X"/"how many X"-shaped input as a status question about
  /// the current results rather than a request to change them. Anything
  /// ending in "?" is always treated as a question, except the "what/how
  /// about X" phrasing above, which is checked first.
  static bool isQuestion(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    final lower = trimmed.toLowerCase();
    if (_newConsiderationStarters.any(lower.startsWith)) return false;
    if (trimmed.endsWith('?')) return true;
    return _questionStarters.any(lower.startsWith);
  }

  static String answer(List<PropertyModel> results, PropertyFilter filter) {
    final count = results.length;
    final locationPhrase = filter.city.isNotEmpty ? ' in ${filter.city}' : '';
    if (count == 0) {
      return "No, I don't have any matches$locationPhrase right now — want to try a different search?";
    }
    if (count == 1) {
      return 'Yes — I found 1 match$locationPhrase.';
    }
    return 'Yes — I found $count matches$locationPhrase.';
  }
}

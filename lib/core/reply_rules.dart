import 'dialogue_state.dart';
import 'register_sensor.dart';

/// Conditional patient response rules — selection only, no generation.
///
/// First matching rule in authored order wins; else [patient_text] fallback.

const Set<String> kAllowedWhenKeys = {
  'prior_asked_any',
  'prior_asked_all',
  'ask_count_gte',
  'trust_gte',
  'register',
  'slots_contains',
  'findings_revealed_any',
  'topic_stack_contains',
};

class ResolvedReply {
  final String text;
  /// Rule index as string, or "fallback".
  final String ruleMatched;

  const ResolvedReply({required this.text, required this.ruleMatched});
}

/// Resolve reply for an intent entry.
///
/// [priorAskCount] must be the count **before** this turn increments
/// [DialogueState.intentAskCount] for [currentIntentId].
ResolvedReply resolveReplyText({
  required Map<String, dynamic> intentEntry,
  required DialogueState state,
  required String currentIntentId,
  required Register register,
  int? priorAskCount,
}) {
  final rulesRaw = intentEntry['rules'];
  final rules = <Map<String, dynamic>>[];
  if (rulesRaw is List) {
    for (final r in rulesRaw) {
      if (r is Map) rules.add(Map<String, dynamic>.from(r));
    }
  }

  final fallback =
      (intentEntry['patient_text'] ?? intentEntry['text'] ?? '') as String;

  if (rules.isEmpty) {
    return ResolvedReply(text: fallback, ruleMatched: 'fallback');
  }

  final askBefore = priorAskCount ?? (state.intentAskCount[currentIntentId] ?? 0);

  for (var i = 0; i < rules.length; i++) {
    final rule = rules[i];
    final when = rule['when'] is Map
        ? Map<String, dynamic>.from(rule['when'] as Map)
        : <String, dynamic>{};
    if (_ruleMatches(when, state, currentIntentId, register, askBefore)) {
      final text = (rule['text'] as String?)?.trim() ?? '';
      if (text.isEmpty) continue;
      return ResolvedReply(text: text, ruleMatched: 'rule_$i');
    }
  }

  return ResolvedReply(text: fallback, ruleMatched: 'fallback');
}

bool _ruleMatches(
  Map<String, dynamic> when,
  DialogueState state,
  String currentIntentId,
  Register register,
  int askCountBeforeThisTurn,
) {
  if (when.containsKey('prior_asked_any')) {
    final ids = (when['prior_asked_any'] as List).cast<String>();
    // "asked before now" = key present with count > 0
    if (!ids.any((id) => (state.intentAskCount[id] ?? 0) > 0)) return false;
  }
  if (when.containsKey('prior_asked_all')) {
    final ids = (when['prior_asked_all'] as List).cast<String>();
    if (!ids.every((id) => (state.intentAskCount[id] ?? 0) > 0)) return false;
  }
  // ask_count_gte: N means 'this intent was already asked at least N times before this turn'.
  // On the 2nd student ask, priorAskCount is 1 → use ask_count_gte: 1 for 'I already told you'.
  if (when.containsKey('ask_count_gte')) {
    final n = (when['ask_count_gte'] as num).toInt();
    if (askCountBeforeThisTurn < n) return false;
  }
  if (when.containsKey('trust_gte')) {
    final t = (when['trust_gte'] as num).toDouble();
    if (state.trust < t) return false;
  }
  if (when.containsKey('register')) {
    if (register.name != when['register']) return false;
  }
  if (when.containsKey('slots_contains')) {
    final key = when['slots_contains'] as String;
    if (!state.slots.containsKey(key)) return false;
  }
  if (when.containsKey('findings_revealed_any')) {
    final ids = (when['findings_revealed_any'] as List).cast<String>();
    if (!ids.any(state.findingsRevealed.contains)) return false;
  }
  if (when.containsKey('topic_stack_contains')) {
    final id = when['topic_stack_contains'] as String;
    if (!state.topicStack.contains(id) && state.activeTopic != id) {
      return false;
    }
  }
  return true;
}

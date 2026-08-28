/// Student question register / tone (v1 heuristic).
///
/// v2 (future): cluster [normText] against author-labeled example phrasings
/// in OnDeviceEncoder embedding space per [Register], instead of heuristics.

enum Register { terse, neutral, anxious }

Register classifyRegister(String normText) {
  final t = normText.trim().toLowerCase();
  if (t.isEmpty) return Register.neutral;

  final words = t.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

  // Anxious / urgent markers
  final anxiousHit = RegExp(
    r"\b(please\s+help|urgent|worried|scared|afraid|emergency|quickly|right\s+now|very\s+concerned|!!!|\?\?)\b",
    caseSensitive: false,
  ).hasMatch(t);
  if (anxiousHit || t.contains('!!') || RegExp(r'\?\s*\?').hasMatch(t)) {
    return Register.anxious;
  }

  // Softening / open exploration → neutral
  final soft = RegExp(
    r"\b(how\s+has|tell\s+me\s+about|could\s+you\s+(describe|tell)|would\s+you\s+mind|please\s+tell|i('d|\s+would)\s+like\s+to\s+know|what\s+has\s+it\s+been\s+like)\b",
    caseSensitive: false,
  ).hasMatch(t);

  // Short closed forms → terse
  final closedShort = RegExp(
    r'^(any|is|are|do|did|does|has|have|was|were)\b',
    caseSensitive: false,
  ).hasMatch(t);

  if (words <= 4 && closedShort && !soft) return Register.terse;
  if (words <= 3 && !soft) return Register.terse;
  if (soft || words >= 6) return Register.neutral;
  if (closedShort) return Register.terse;
  return Register.neutral;
}

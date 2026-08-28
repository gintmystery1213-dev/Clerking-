/// Phase 4 — Safety / danger module (global + case traps).

class SafetyHit {
  final String explanation;
  final int penalty;
  final String source; // global | case

  SafetyHit({
    required this.explanation,
    required this.penalty,
    this.source = 'global',
  });
}

final List<Map<String, dynamic>> kGlobalDangerousPatterns = [
  {
    'pattern': RegExp(r'\b(give|administer|inject)\s+(morphine|pethidine|opioid)\b', caseSensitive: false),
    'explanation': 'Do not administer potent opioids without assessment and supervision in this simulation context.',
    'penalty': 15,
  },
  {
    'pattern': RegExp(r'\b(discharge\s+(home|the patient)|send\s+(him|her|them)\s+home)\b', caseSensitive: false),
    'explanation': 'Discharging without adequate assessment is unsafe.',
    'penalty': 12,
  },
  {
    'pattern': RegExp(r'\b(ignore|don.?t\s+examine|no\s+need\s+to\s+examine)\b', caseSensitive: false),
    'explanation': 'Skipping examination when clinically indicated is unsafe practice.',
    'penalty': 8,
  },
];

SafetyHit? evaluateSafety(String normText, Map<String, dynamic> caseData) {
  final traps = caseData['trapActions'] as List? ?? caseData['traps'] as List?;
  if (traps != null) {
    for (final trap in traps) {
      if (trap is! Map) continue;
      final t = Map<String, dynamic>.from(trap);
      final pat = t['pattern'];
      RegExp re;
      if (pat is RegExp) {
        re = pat;
      } else if (pat is String && pat.isNotEmpty) {
        re = RegExp(pat, caseSensitive: false);
      } else {
        continue;
      }
      if (re.hasMatch(normText)) {
        return SafetyHit(
          explanation: t['explanation'] as String? ?? 'Unsafe action',
          penalty: (t['penalty'] as num?)?.toInt() ?? 10,
          source: 'case',
        );
      }
    }
  }
  for (final g in kGlobalDangerousPatterns) {
    if ((g['pattern'] as RegExp).hasMatch(normText)) {
      return SafetyHit(
        explanation: g['explanation'] as String,
        penalty: g['penalty'] as int,
        source: 'global',
      );
    }
  }
  return null;
}

import 'embeddings.dart';
import 'intent_patterns.dart';
import 'on_device_encoder.dart';

/// Soft semantic-ish matching without an external embedding model:
/// token overlap, character n-grams, synonym expansion, negation awareness.

const Map<String, List<String>> kSynonyms = {
  'fever': ['pyrexia', 'febrile', 'temperature', 'hot', 'feverish', 'feva'],
  'vomit': ['vomiting', 'vomited', 'throw up', 'emesis', 'nausea'],
  'diarrhoea': ['diarrhea', 'loose stool', 'watery stool', 'runny stool'],
  'cough': ['coughing', 'coughs'],
  'breath': ['breathing', 'dyspnoea', 'dyspnea', 'shortness of breath', 'sob', 'respiratory'],
  'pain': ['ache', 'aching', 'hurt', 'hurting', 'sore', 'discomfort'],
  'onset': ['start', 'began', 'begin', 'started', 'when', 'how long', 'duration', 'since'],
  'feeding': ['breastfeed', 'breastfeeding', 'formula', 'suck', 'sucking', 'intake', 'eating'],
  'birth': ['delivery', 'labour', 'labor', 'born', 'neonatal', 'perinatal', 'apgar'],
  'jaundice': ['yellow', 'yellowing', 'icterus', 'bilirubin'],
  'seizure': ['fit', 'convulsion', 'convulse', 'jerking', 'shaking'],
  'rash': ['spots', 'eruption', 'skin lesion'],
  'travel': ['travelled', 'traveled', 'trip', 'abroad', 'village'],
  'medication': ['medicine', 'drug', 'drugs', 'tablet', 'syrup', 'treatment'],
  'allergy': ['allergies', 'allergic', 'reaction'],
};

const Set<String> kNegationCues = {
  'no', 'not', 'never', 'without', 'denies', 'deny', 'denied',
  'nil', 'none', 'absence', 'absent', "doesn't", 'doesnt', "didn't",
  'didnt', "hasn't", 'hasnt', "haven't", 'havent', 'negative',
};

const Set<String> kStopwords = {
  'the', 'a', 'an', 'is', 'are', 'was', 'were', 'be', 'been', 'do', 'did',
  'does', 'to', 'of', 'in', 'on', 'at', 'for', 'and', 'or', 'but', 'with',
  'you', 'your', 'me', 'my', 'we', 'our', 'any', 'some', 'please', 'doctor',
  'about', 'tell', 'can', 'could', 'would', 'will', 'i', 'he', 'she', 'it',
  'his', 'her', 'their', 'this', 'that', 'there', 'have', 'has', 'had',
};

class ScoredIntent {
  final Map<String, dynamic> pattern;
  final double score;
  final bool phraseHit;
  final bool softHit;

  ScoredIntent({
    required this.pattern,
    required this.score,
    this.phraseHit = false,
    this.softHit = false,
  });

  String get id => pattern['id'] as String;
}

Set<String> expandTokens(String text) {
  final raw = text
      .toLowerCase()
      .replaceAll(RegExp(r"[^\w\s']"), ' ')
      .split(RegExp(r'\s+'))
      .where((t) => t.isNotEmpty && !kStopwords.contains(t))
      .toSet();

  final out = <String>{...raw};
  for (final t in raw) {
    for (final e in kSynonyms.entries) {
      if (e.key == t || e.value.contains(t)) {
        out.add(e.key);
        out.addAll(e.value.map((v) => v.split(' ').first));
      }
    }
    // light stem: drop trailing s/ing/ed
    if (t.endsWith('ing') && t.length > 5) out.add(t.substring(0, t.length - 3));
    if (t.endsWith('ed') && t.length > 4) out.add(t.substring(0, t.length - 2));
    if (t.endsWith('s') && t.length > 3) out.add(t.substring(0, t.length - 1));
  }
  return out;
}

bool hasNegation(String normText) {
  final tokens = normText.toLowerCase().split(RegExp(r'\s+'));
  return tokens.any(kNegationCues.contains);
}

/// Character 3-gram Jaccard for fuzzy phrase similarity.
double ngramSimilarity(String a, String b) {
  Set<String> grams(String s) {
    final t = s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    if (t.length < 3) return {t};
    return {for (var i = 0; i <= t.length - 3; i++) t.substring(i, i + 3)};
  }

  final ga = grams(a);
  final gb = grams(b);
  if (ga.isEmpty || gb.isEmpty) return 0;
  final inter = ga.intersection(gb).length;
  final union = ga.union(gb).length;
  return inter / union;
}

double tokenOverlap(Set<String> a, Set<String> b) {
  if (a.isEmpty || b.isEmpty) return 0;
  return a.intersection(b).length / a.union(b).length;
}

/// Score all intents; returns sorted list (best first).
List<ScoredIntent> rankIntents(
  String normText,
  List<Map<String, dynamic>> patterns, {
  String? topicBoostId,
  bool includeVectors = true,
}) {
  final studentTokens = expandTokens(normText);
  final negated = hasNegation(normText);
  final scored = <ScoredIntent>[];

  for (final pattern in patterns) {
    var score = 0.0;
    var phraseHit = false;
    var softHit = false;

    final phrases = (pattern['phrases'] as List? ?? []).cast<String>();
    for (final phrase in phrases) {
      final pl = phrase.toLowerCase();
      if (normText.contains(pl)) {
        score += 30;
        phraseHit = true;
      } else {
        final sim = ngramSimilarity(normText, pl);
        if (sim >= 0.45) {
          score += 18 * sim;
          softHit = true;
        }
      }
    }

    final keywords = (pattern['keywords'] as List? ?? []).cast<String>();
    var keywordHits = 0;
    final kwTokens = <String>{};
    for (final kw in keywords) {
      final kwLower = kw.toLowerCase();
      kwTokens.addAll(expandTokens(kwLower));
      if (normText.contains(kwLower)) {
        if (kw.length <= 4) {
          if (RegExp('\\b${RegExp.escape(kwLower)}\\b').hasMatch(normText)) {
            score += 10;
            keywordHits++;
          }
        } else {
          score += 10;
          keywordHits++;
        }
      }
    }

    // Soft token overlap against keyword bag
    final overlap = tokenOverlap(studentTokens, kwTokens);
    if (overlap > 0.15) {
      score += 25 * overlap;
      softHit = true;
    }

    if (keywordHits >= 2) score += 10;
    if (keywordHits >= 4) score += 10;

    // Topic continuity boost
    if (topicBoostId != null && pattern['id'] == topicBoostId) {
      score += 12;
    }

    // Negation: downrank positive symptom intents slightly when user denies
    // (student saying "any fever?" is not negation; "no fever history?" is messy —
    // only penalise if negation + symptom keyword both present strongly)
    if (negated && keywordHits > 0 && !phraseHit) {
      score *= 0.85;
    }

    if (score > 0) {
      scored.add(ScoredIntent(
        pattern: pattern,
        score: score,
        phraseHit: phraseHit,
        softHit: softHit,
      ));
    }
  }

  // Vector embedding boost (optional — fusion layer may own vectors)
  final embHits = <String, double>{};
  if (includeVectors && OnDeviceEncoder.instance.loaded) {
    for (final h in OnDeviceEncoder.instance.rankIntents(normText, topK: 15)) {
      embHits[h.id] = h.score;
    }
  } else if (includeVectors && EmbeddingIndex.instance.loaded) {
    for (final h in EmbeddingIndex.instance.rankLsa(normText, topK: 15)) {
      embHits[h.id] = h.score;
    }
  }
  if (embHits.isNotEmpty) {
    for (var i = 0; i < scored.length; i++) {
      final sim = embHits[scored[i].id] ?? 0.0;
      if (sim > 0.15) {
        scored[i] = ScoredIntent(
          pattern: scored[i].pattern,
          score: scored[i].score + sim * 40,
          phraseHit: scored[i].phraseHit,
          softHit: true,
        );
      }
    }
    final byId = {for (final s in scored) s.id: s};
    for (final h in embHits.entries) {
      if (h.value < 0.32) continue;
      if (byId.containsKey(h.key)) continue;
      Map<String, dynamic>? pat;
      for (final p in patterns) {
        if (p['id'] == h.key) {
          pat = p;
          break;
        }
      }
      if (pat == null) continue;
      scored.add(ScoredIntent(
        pattern: pat,
        score: h.value * 45,
        softHit: true,
      ));
    }
  }

  scored.sort((a, b) => b.score.compareTo(a.score));
  return scored;
}

/// Multi-intent: all above threshold, or top ambiguous pair for clarification.
class MatchDecision {
  final List<ScoredIntent> matches;
  final ScoredIntent? clarificationCandidate;
  final bool unmatched;

  MatchDecision({
    required this.matches,
    this.clarificationCandidate,
    this.unmatched = false,
  });
}

MatchDecision decideMatches(
  String normText,
  List<Map<String, dynamic>> patterns, {
  String? topicBoostId,
  double highThreshold = 22,
  double midThreshold = 14,
  double multiThreshold = 20,
}) {
  final ranked = rankIntents(normText, patterns, topicBoostId: topicBoostId);
  if (ranked.isEmpty) {
    return MatchDecision(matches: [], unmatched: true);
  }

  final best = ranked.first;

  // High confidence single or multi
  final multi = ranked
      .where((s) => s.score >= multiThreshold)
      .take(3)
      .toList();

  if (best.score >= highThreshold) {
    // If second is close and also strong, return multi
    if (multi.length >= 2 &&
        (best.score - multi[1].score) < 12 &&
        multi[1].score >= multiThreshold) {
      return MatchDecision(matches: multi);
    }
    return MatchDecision(matches: [best]);
  }

  // Medium → clarification candidate
  if (best.score >= midThreshold) {
    return MatchDecision(
      matches: [],
      clarificationCandidate: best,
    );
  }

  return MatchDecision(matches: [], unmatched: true);
}

/// Slot extraction from student question or patient reply text.
Map<String, String> extractSlots(String text) {
  final slots = <String, String>{};
  final duration = RegExp(
    r'(\d+)\s*(day|days|week|weeks|month|months|year|years|hour|hours)',
    caseSensitive: false,
  );
  final m = duration.firstMatch(text);
  if (m != null) slots['duration'] = m.group(0)!;

  final onsetDay = RegExp(r'day\s*(\d+)', caseSensitive: false);
  final od = onsetDay.firstMatch(text);
  if (od != null) slots['onset_day'] = 'day ${od.group(1)}';

  final age = RegExp(r'(\d+)\s*(year|years|month|months|week|weeks)\s*old', caseSensitive: false);
  final a = age.firstMatch(text);
  if (a != null) slots['age_mentioned'] = a.group(0)!;

  return slots;
}

bool isAffirmative(String normText) {
  return RegExp(
    r'^\s*(yes|yeah|yep|correct|right|exactly|sure|ok|okay|please|go ahead)\b',
    caseSensitive: false,
  ).hasMatch(normText.trim());
}

bool isNegativeReply(String normText) {
  return RegExp(
    r'^\s*(no|nope|not really|never mind|wrong|incorrect)\b',
    caseSensitive: false,
  ).hasMatch(normText.trim());
}

bool isTellMore(String normText) {
  return RegExp(
    r'\b(tell me more|more detail|elaborate|go on|continue|what else|anything else about)\b',
    caseSensitive: false,
  ).hasMatch(normText);
}

bool isShortFollowUp(String normText) {
  final words = normText.trim().split(RegExp(r'\s+'));
  if (words.length > 8) return false;
  return RegExp(
    r'\b(how long|when|where|how often|how much|still|again|and before|before that|after that|was it|is it|any other)\b',
    caseSensitive: false,
  ).hasMatch(normText);
}

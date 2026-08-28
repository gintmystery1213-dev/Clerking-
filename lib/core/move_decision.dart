import 'intent_patterns.dart';
import 'on_device_encoder.dart';
import 'ontology.dart';
import 'soft_match.dart';
import 'dialogue_state.dart';

/// Phase 1 — Fused move decision: keywords + soft + vectors are sensors only.

enum MatchSource { phrase, keyword, soft, vector, fused, topicPrior }

class ScoredCandidate {
  final String intentId;
  final Map<String, dynamic> pattern;
  final double keywordScore;
  final double softScore;
  final double vectorScore;
  final double fusedScore;
  final MatchSource primarySource;

  ScoredCandidate({
    required this.intentId,
    required this.pattern,
    this.keywordScore = 0,
    this.softScore = 0,
    this.vectorScore = 0,
    required this.fusedScore,
    required this.primarySource,
  });
}

class MoveDecision {
  final List<ScoredCandidate> matches;
  final double confidence;
  final ClinicalPhase phase;
  final SpeechAct speechAct;
  final bool unmatched;
  final String? reason;

  MoveDecision({
    required this.matches,
    required this.confidence,
    required this.phase,
    required this.speechAct,
    this.unmatched = false,
    this.reason,
  });

  bool get hasMatch => matches.isNotEmpty;
  ScoredCandidate? get best => matches.isEmpty ? null : matches.first;
}


Map<String, dynamic>? patternById(String id) {
  for (final p in kIntentPatterns) {
    if (p['id'] == id) return p;
  }
  return null;
}

/// Tunable fusion weights & thresholds (Phase 1).
class FusionConfig {
  final double wKeyword;
  final double wSoft;
  final double wVector;
  final double topicBoost;
  final double phaseBoost;
  final double highThreshold;
  final double midThreshold;
  final double multiThreshold;
  final double vectorOnlyMin;

  const FusionConfig({
    this.wKeyword = 1.0,
    this.wSoft = 0.85,
    this.wVector = 1.15,
    this.topicBoost = 12,
    this.phaseBoost = 8,
    this.highThreshold = 24,
    this.midThreshold = 14,
    this.multiThreshold = 22,
    this.vectorOnlyMin = 0.34,
  });
}

/// Keyword/phrase-only sensor (precision).
Map<String, double> keywordSensor(String normText) {
  final out = <String, double>{};
  for (final pattern in kIntentPatterns) {
    final id = pattern['id'] as String;
    var score = 0.0;
    for (final phrase in (pattern['phrases'] as List? ?? []).cast<String>()) {
      if (normText.contains(phrase.toLowerCase())) score += 30;
    }
    for (final kw in (pattern['keywords'] as List? ?? []).cast<String>()) {
      final k = kw.toLowerCase();
      if (k.length <= 4) {
        if (RegExp('\\b${RegExp.escape(k)}\\b').hasMatch(normText)) score += 10;
      } else if (normText.contains(k)) {
        score += 10;
      }
    }
    if (score > 0) out[id] = score;
  }
  return out;
}

/// Soft lexical sensor.
Map<String, double> softSensor(String normText) {
  final ranked = rankIntents(normText, kIntentPatterns, includeVectors: false);
  return {for (final s in ranked) s.id: s.score};
}

/// Vector sensor (on-device MiniLM-static).
Map<String, double> vectorSensor(String normText) {
  if (!OnDeviceEncoder.instance.loaded) return {};
  final ranked = OnDeviceEncoder.instance.rankIntents(normText, topK: 20);
  // Map cosine ~0..1 → comparable points
  return {for (final h in ranked) h.id: h.score * 50};
}

MoveDecision resolveMove({
  required String normText,
  required DialogueState state,
  required Map<String, dynamic> caseData,
  FusionConfig config = const FusionConfig(),
}) {
  final phase = detectPhase(normText);
  final act = detectSpeechAct(normText);
  final intentMap = caseData['intentMap'] as Map<String, dynamic>? ?? {};

  // Topic-bound short follow-up: strong prior
  if (state.activeTopic != null &&
      intentMap.containsKey(state.activeTopic) &&
      (isShortFollowUp(normText) || isTellMore(normText))) {
    final id = state.activeTopic!;
    final pat = patternById(id);
    return MoveDecision(
      matches: [
        ScoredCandidate(
          intentId: id,
          pattern: pat ?? {'id': id, 'keywords': [], 'phrases': []},
          fusedScore: 40,
          primarySource: MatchSource.topicPrior,
        ),
      ],
      confidence: 0.88,
      phase: phase,
      speechAct: act,
      reason: 'topic_followup',
    );
  }

  final kw = keywordSensor(normText);
  final soft = softSensor(normText);
  final vec = vectorSensor(normText);

  final ids = <String>{...kw.keys, ...soft.keys, ...vec.keys};
  final candidates = <ScoredCandidate>[];

  for (final id in ids) {
    final k = kw[id] ?? 0;
    final s = soft[id] ?? 0;
    final v = vec[id] ?? 0;
    var fused = config.wKeyword * k + config.wSoft * s * 0.5 + config.wVector * v;

    if (state.activeTopic == id) fused += config.topicBoost;
    if (phaseForIntent(id) == phase) fused += config.phaseBoost;

    // Already asked: still match for dialogue, fusion slightly down for ranking only
    if (state.intentAskCount.containsKey(id)) fused *= 0.92;

    MatchSource src = MatchSource.fused;
    final bestPart = [k, s, v].reduce((a, b) => a > b ? a : b);
    if (bestPart == k && k >= s && k >= v) src = MatchSource.phrase;
    else if (bestPart == v && v > k && v > s) src = MatchSource.vector;
    else if (bestPart == s) src = MatchSource.soft;

    // Vector-only weak hits: require minimum cosine-equivalent
    if (k < 8 && s < 12 && (vec[id] ?? 0) < config.vectorOnlyMin * 50) {
      continue;
    }

    final pat = patternById(id);
    if (pat == null) continue;

    candidates.add(ScoredCandidate(
      intentId: id,
      pattern: pat,
      keywordScore: k,
      softScore: s,
      vectorScore: v,
      fusedScore: fused,
      primarySource: src,
    ));
  }

  candidates.sort((a, b) => b.fusedScore.compareTo(a.fusedScore));
  if (candidates.isEmpty) {
    return MoveDecision(
      matches: [],
      confidence: 0,
      phase: phase,
      speechAct: act,
      unmatched: true,
      reason: 'no_sensor_hit',
    );
  }

  final best = candidates.first;

  // High confidence single or multi
  if (best.fusedScore >= config.highThreshold) {
    final multi = candidates
        .where((c) => c.fusedScore >= config.multiThreshold)
        .take(3)
        .toList();
    if (multi.length >= 2 &&
        (best.fusedScore - multi[1].fusedScore) < 14 &&
        multi[1].fusedScore >= config.multiThreshold) {
      return MoveDecision(
        matches: multi,
        confidence: (best.fusedScore / 50).clamp(0.0, 1.0),
        phase: phase,
        speechAct: act,
        reason: 'multi_fused',
      );
    }
    return MoveDecision(
      matches: [best],
      confidence: (best.fusedScore / 50).clamp(0.0, 1.0),
      phase: phase,
      speechAct: act,
      reason: 'high_fused',
    );
  }

  // Mid — still no tutor clarification labels; treat as weak
  if (best.fusedScore >= config.midThreshold) {
    return MoveDecision(
      matches: [best],
      confidence: (best.fusedScore / 50).clamp(0.0, 0.55),
      phase: phase,
      speechAct: act,
      reason: 'mid_fused',
    );
  }

  return MoveDecision(
    matches: [],
    confidence: (best.fusedScore / 50).clamp(0.0, 0.4),
    phase: phase,
    speechAct: act,
    unmatched: true,
    reason: 'below_threshold',
  );
}

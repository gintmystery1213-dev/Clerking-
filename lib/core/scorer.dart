import 'ontology.dart';

/// Phase 4 — Scoring module (case scoringMap only; deterministic).

class ScoreEvent {
  final String intentId;
  final int points;
  final String band; // must | should | other | none
  final bool repeat;

  ScoreEvent({
    required this.intentId,
    required this.points,
    required this.band,
    this.repeat = false,
  });
}

class ScoreResult {
  final int totalDelta;
  final List<ScoreEvent> events;

  ScoreResult({required this.totalDelta, required this.events});
}

ScoreResult scoreMoves({
  required List<String> intentIds,
  required Map<String, dynamic> scoringMap,
  required List<String> alreadyAsked,
  bool awardRepeats = false,
}) {
  final events = <ScoreEvent>[];
  var total = 0;
  final must = (scoringMap['mustAsk'] as List?)?.cast<String>() ?? [];
  final should = (scoringMap['shouldAsk'] as List?)?.cast<String>() ?? [];
  final pointsMust = (scoringMap['pointsMust'] as num?)?.toInt() ?? 15;
  final pointsBase = (scoringMap['pointsBase'] as num?)?.toInt() ?? 10;

  for (final id in intentIds) {
    final repeat = alreadyAsked.contains(id);
    if (repeat && !awardRepeats) {
      events.add(ScoreEvent(intentId: id, points: 0, band: 'none', repeat: true));
      continue;
    }
    late int pts;
    late String band;
    if (must.contains(id)) {
      pts = pointsMust;
      band = 'must';
    } else if (should.contains(id)) {
      pts = pointsBase;
      band = 'should';
    } else {
      pts = 5;
      band = 'other';
    }
    total += pts;
    events.add(ScoreEvent(intentId: id, points: pts, band: band, repeat: repeat));
  }
  return ScoreResult(totalDelta: total, events: events);
}

/// Sequence penalty: synthesis/management before any must-ask history covered.
int sequencePenalty({
  required ClinicalPhase phase,
  required List<String> askedIntents,
  required Map<String, dynamic> scoringMap,
}) {
  final must = (scoringMap['mustAsk'] as List?)?.cast<String>() ?? [];
  if (must.isEmpty) return 0;
  final anyMust = must.any(askedIntents.contains);
  if (!anyMust &&
      (phase == ClinicalPhase.synthesis || phase == ClinicalPhase.management)) {
    return 10;
  }
  return 0;
}

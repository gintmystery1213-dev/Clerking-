import 'dialogue_state.dart';
import 'engine.dart';
import 'miss_log.dart';
import 'move_decision.dart';
import 'on_device_encoder.dart';

/// Phase 5 — Matcher quality loop: fixtures + runner.

class RegressionExample {
  final String caseId;
  final String utterance;
  final String? expectedIntentId;
  final bool expectUnmatched;
  /// If set, expected type substring e.g. match, negative, penalty
  final String? expectedType;

  const RegressionExample({
    required this.caseId,
    required this.utterance,
    this.expectedIntentId,
    this.expectUnmatched = false,
    this.expectedType,
  });
}

/// Seed fixtures — paraphrases, local phrasing, and deliberate misses.
const List<RegressionExample> kRegressionFixtures = [
  // Onset paraphrases
  RegressionExample(
    caseId: 'any',
    utterance: 'When did the yellowing start?',
    expectedIntentId: 'hpc_onset',
  ),
  RegressionExample(
    caseId: 'any',
    utterance: 'How long has this been going on?',
    expectedIntentId: 'hpc_onset',
  ),
  RegressionExample(
    caseId: 'any',
    utterance: 'When did you first notice the yellow colour?',
    expectedIntentId: 'hpc_onset',
  ),
  RegressionExample(
    caseId: 'any',
    utterance: 'Since when has the pikin body dey yellow?',
    expectedIntentId: 'hpc_onset',
  ),

  // Character / description
  RegressionExample(
    caseId: 'any',
    utterance: 'Can you describe the jaundice?',
    expectedIntentId: 'hpc_character',
  ),
  RegressionExample(
    caseId: 'any',
    utterance: 'What does the yellowing look like?',
    expectedIntentId: 'hpc_character',
  ),

  // Birth / feeding
  RegressionExample(
    caseId: 'any',
    utterance: 'Tell me about the birth history',
    expectedIntentId: 'birth_history',
  ),
  RegressionExample(
    caseId: 'any',
    utterance: 'How was the delivery?',
    expectedIntentId: 'birth_history',
  ),
  RegressionExample(
    caseId: 'any',
    utterance: 'Is the baby feeding well?',
    expectedIntentId: 'feeding_history',
  ),
  RegressionExample(
    caseId: 'any',
    utterance: 'How is breastfeeding going?',
    expectedIntentId: 'feeding_history',
  ),

  // Exam / Ix
  RegressionExample(
    caseId: 'any',
    utterance: 'I would like to examine the baby generally',
    expectedIntentId: 'exam_general',
  ),
  RegressionExample(
    caseId: 'any',
    utterance: 'Let me examine the skin',
    expectedIntentId: 'exam_skin',
  ),
  RegressionExample(
    caseId: 'any',
    utterance: 'I want to order serum bilirubin',
    expectedIntentId: 'ix_bilirubin',
  ),
  RegressionExample(
    caseId: 'any',
    utterance: 'Please request an FBC',
    expectedIntentId: 'ix_fbc',
  ),

  // Fever systems review
  RegressionExample(
    caseId: 'any',
    utterance: 'Any fever?',
    expectedIntentId: 'sr_fever',
  ),
  RegressionExample(
    caseId: 'any',
    utterance: 'Has the baby been hot?',
    expectedIntentId: 'sr_fever',
  ),

  // Deliberate unmatched / off-topic
  RegressionExample(
    caseId: 'any',
    utterance: 'What is the capital of France?',
    expectUnmatched: true,
  ),
  RegressionExample(
    caseId: 'any',
    utterance: 'Who won the football match yesterday?',
    expectUnmatched: true,
  ),
];

class FixtureResult {
  final RegressionExample example;
  final bool passed;
  final String? gotIntentId;
  final String? gotType;
  final double? confidence;
  final String? matchSource;
  final String detail;

  FixtureResult({
    required this.example,
    required this.passed,
    this.gotIntentId,
    this.gotType,
    this.confidence,
    this.matchSource,
    required this.detail,
  });
}

class RegressionReport {
  final int total;
  final int passed;
  final int failed;
  final List<FixtureResult> results;

  RegressionReport({
    required this.total,
    required this.passed,
    required this.failed,
    required this.results,
  });

  double get passRate => total == 0 ? 0 : passed / total;

  @override
  String toString() {
    final buf = StringBuffer();
    buf.writeln('Regression: $passed/$total passed (${(passRate * 100).toStringAsFixed(1)}%)');
    for (final r in results.where((x) => !x.passed)) {
      buf.writeln('  FAIL: "${r.example.utterance}" → ${r.detail}');
    }
    return buf.toString();
  }
}

/// Minimal synthetic case when real JSON is not loaded (unit / headless).
Map<String, dynamic> syntheticJaundiceCase() {
  return {
    'caseId': 'case_peds_neonatal_jaundice_001',
    'discipline': 'peds',
    'presentingComplaint': 'Yellow discolouration of skin and eyes',
    'patient': {
      'name': 'Baby Test',
      'age': 0,
      'sex': 'Male',
      'avatar': '🍼',
    },
    'diagnosis': {'primary': 'Neonatal Jaundice (Physiological)'},
    'scoringMap': {
      'mustAsk': ['hpc_onset', 'birth_history', 'feeding_history', 'ix_bilirubin'],
      'shouldAsk': ['exam_general', 'ix_fbc'],
      'pointsMust': 15,
      'pointsBase': 10,
    },
    'intentMap': {
      for (final id in [
        'hpc_onset',
        'hpc_character',
        'birth_history',
        'feeding_history',
        'blood_group',
        'fhx_general',
        'sr_fever',
        'exam_general',
        'exam_skin',
        'exam_abdomen',
        'ix_bilirubin',
        'ix_fbc',
        'ix_bloodgroup',
      ])
        id: {
          'label': id,
          'patient_text': 'Test reply for $id.',
          'type': 'history',
        },
    },
    'trapActions': [],
  };
}

/// Run all fixtures against [caseData] (or synthetic jaundice case).
///
/// Loads [OnDeviceEncoder] if not already loaded (call from Flutter after binding).
Future<RegressionReport> runRegression({
  Map<String, dynamic>? caseData,
  List<RegressionExample>? fixtures,
  bool useProcessChat = true,
}) async {
  final data = caseData ?? syntheticJaundiceCase();
  final list = fixtures ?? kRegressionFixtures;
  final results = <FixtureResult>[];

  // Encoder may already be loaded from main(); ignore if assets unavailable
  try {
    if (!OnDeviceEncoder.instance.loaded) {
      await OnDeviceEncoder.instance.load();
    }
  } catch (_) {
    // Headless / missing assets: keyword+soft sensors still run
  }

  for (final ex in list) {
    final state = DialogueState();
    if (useProcessChat) {
      final chat = processChat(
        caseData: data,
        message: ex.utterance,
        askedIntents: const [],
        dialogue: state,
      );
      final got = chat.intentId;
      final type = chat.type;
      final ok = _evaluate(ex, got, type);
      results.add(FixtureResult(
        example: ex,
        passed: ok,
        gotIntentId: got,
        gotType: type,
        confidence: chat.confidence,
        matchSource: chat.matchSource,
        detail: ok
            ? 'OK ($type, $got)'
            : 'expected=${ex.expectUnmatched ? "unmatched" : ex.expectedIntentId} '
                'got=$got type=$type src=${chat.matchSource}',
      ));
    } else {
      final norm = normaliseText(ex.utterance);
      final decision = resolveMove(
        normText: norm,
        state: state,
        caseData: data,
      );
      final got = decision.best?.intentId;
      final unmatched = decision.unmatched || !decision.hasMatch;
      final ok = ex.expectUnmatched
          ? unmatched
          : (!unmatched && got == ex.expectedIntentId);
      results.add(FixtureResult(
        example: ex,
        passed: ok,
        gotIntentId: got,
        confidence: decision.confidence,
        matchSource: decision.reason,
        detail: ok
            ? 'OK'
            : 'expected=${ex.expectUnmatched ? "unmatched" : ex.expectedIntentId} '
                'got=$got conf=${decision.confidence.toStringAsFixed(2)}',
      ));
    }
  }

  final passed = results.where((r) => r.passed).length;
  return RegressionReport(
    total: results.length,
    passed: passed,
    failed: results.length - passed,
    results: results,
  );
}

bool _evaluate(RegressionExample ex, String? gotIntent, String type) {
  final unmatchedTypes = {
    'negative',
    'near_miss',
    'fallback',
    'not_applicable',
  };
  if (ex.expectUnmatched) {
    return unmatchedTypes.contains(type) || gotIntent == null;
  }
  if (ex.expectedType != null && type != ex.expectedType) return false;
  if (ex.expectedIntentId == null) return true;
  // Accept primary intent or multi containing it
  if (gotIntent == ex.expectedIntentId) return true;
  // Weak match still counts if intent correct
  if (gotIntent == ex.expectedIntentId) return true;
  return false;
}

Map<String, int> missReasonHistogram() {
  final hist = <String, int>{};
  for (final e in MissLog.instance.snapshot()) {
    final r = e['reason']?.toString() ?? 'unknown';
    hist[r] = (hist[r] ?? 0) + 1;
  }
  return hist;
}

List<String> topMissedUtterances({int limit = 20}) {
  return MissLog.instance
      .snapshot()
      .map((e) => e['message']?.toString() ?? '')
      .where((m) => m.isNotEmpty)
      .take(limit)
      .toList();
}

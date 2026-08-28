import 'reply_rules.dart';

/// Phase 0 — Case schema validation (authoring contract).

class CaseValidation {
  final bool ok;
  final List<String> errors;
  final List<String> warnings;

  CaseValidation({
    required this.ok,
    this.errors = const [],
    this.warnings = const [],
  });
}

CaseValidation validateCase(Map<String, dynamic> caseData) {
  final errors = <String>[];
  final warnings = <String>[];

  final id = caseData['caseId'] ?? caseData['id'];
  if (id == null || '$id'.isEmpty) errors.add('missing caseId');

  final intentMap = caseData['intentMap'];
  if (intentMap is! Map || intentMap.isEmpty) {
    errors.add('intentMap missing or empty');
  } else {
    final intentKeys = intentMap.keys.map((k) => '$k').toSet();

    for (final e in intentMap.entries) {
      final key = '${e.key}';
      final v = e.value;
      if (v is! Map) {
        errors.add('intent $key is not a map');
        continue;
      }
      final entry = Map<String, dynamic>.from(v);
      final pt = entry['patient_text'] ?? entry['text'];
      final hasRules = entry['rules'] is List && (entry['rules'] as List).isNotEmpty;

      if (pt == null || '$pt'.trim().isEmpty) {
        errors.add('intent $key missing patient_text');
      }
      if (entry['examiner_text'] != null && entry['patient_text'] == null) {
        warnings.add(
          'intent $key has examiner_text only — live path must not use it',
        );
      }

      if (hasRules) {
        if (pt == null || '$pt'.trim().isEmpty) {
          errors.add(
            'intent $key has rules but missing mandatory patient_text fallback',
          );
        }
        final rules = entry['rules'] as List;
        for (var i = 0; i < rules.length; i++) {
          final r = rules[i];
          if (r is! Map) {
            errors.add('intent $key rules[$i] is not a map');
            continue;
          }
          final rule = Map<String, dynamic>.from(r);
          final text = rule['text'];
          if (text == null || '$text'.trim().isEmpty) {
            errors.add('intent $key rules[$i] missing text');
          }
          final when = rule['when'];
          if (when != null && when is! Map) {
            errors.add('intent $key rules[$i].when must be an object');
            continue;
          }
          if (when is Map) {
            for (final wk in when.keys) {
              if (!kAllowedWhenKeys.contains('$wk')) {
                errors.add(
                  'intent $key rules[$i] unknown when key: $wk',
                );
              }
            }
            void checkIntentRefs(String op) {
              final list = when[op];
              if (list is List) {
                for (final ref in list) {
                  if (!intentKeys.contains('$ref')) {
                    warnings.add(
                      'intent $key rules[$i].$op references unknown $ref',
                    );
                  }
                }
              }
            }

            checkIntentRefs('prior_asked_any');
            checkIntentRefs('prior_asked_all');
            checkIntentRefs('findings_revealed_any');

            if (when.containsKey('trust_gte')) {
              final t = when['trust_gte'];
              if (t is! num || t < 0.0 || t > 1.0) {
                errors.add(
                  'intent $key rules[$i].trust_gte must be in [0.0, 1.0]',
                );
              }
            }
            if (when.containsKey('ask_count_gte')) {
              final n = when['ask_count_gte'];
              if (n is! num || n != n.roundToDouble() || n < 1) {
                errors.add(
                  'intent $key rules[$i].ask_count_gte must be a positive integer',
                );
              }
            }
            if (when.containsKey('register')) {
              final r = '${when['register']}';
              if (r != 'terse' && r != 'neutral' && r != 'anxious') {
                errors.add(
                  'intent $key rules[$i].register must be terse|neutral|anxious',
                );
              }
            }
          }
        }
      }
    }
  }

  final scoring = caseData['scoringMap'];
  if (scoring is! Map) {
    errors.add('scoringMap missing');
  } else if (intentMap is Map) {
    for (final key in ['mustAsk', 'shouldAsk']) {
      final list = scoring[key];
      if (list is List) {
        for (final intentId in list) {
          if (!intentMap.containsKey(intentId)) {
            warnings.add('$key references unknown intent $intentId');
          }
        }
      }
    }
  }

  if (caseData['patient'] is! Map) warnings.add('patient profile missing');
  if (caseData['presentingComplaint'] == null &&
      caseData['presenting_complaint'] == null) {
    warnings.add('presentingComplaint missing');
  }

  return CaseValidation(ok: errors.isEmpty, errors: errors, warnings: warnings);
}

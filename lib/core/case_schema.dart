/// Phase 0 — Case schema validation (authoring contract).

class CaseValidation {
  final bool ok;
  final List<String> errors;
  final List<String> warnings;

  CaseValidation({required this.ok, this.errors = const [], this.warnings = const []});
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
    for (final e in intentMap.entries) {
      final v = e.value;
      if (v is! Map) {
        errors.add('intent ${e.key} is not a map');
        continue;
      }
      final pt = v['patient_text'] ?? v['text'];
      if (pt == null || '$pt'.trim().isEmpty) {
        errors.add('intent ${e.key} missing patient_text');
      }
      if (v['examiner_text'] != null && v['patient_text'] == null) {
        warnings.add('intent ${e.key} has examiner_text only — live path must not use it');
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

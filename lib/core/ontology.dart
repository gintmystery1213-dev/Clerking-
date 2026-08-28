/// Phase 2 — Fixed clinical move ontology (case-agnostic intent catalog).

enum ClinicalPhase {
  history,
  examination,
  investigation,
  synthesis,
  management,
  meta,
}

ClinicalPhase phaseForIntent(String intentId) {
  if (intentId.startsWith('ix_') || intentId.startsWith('invest')) {
    return ClinicalPhase.investigation;
  }
  if (intentId.startsWith('exam_')) return ClinicalPhase.examination;
  if (intentId.startsWith('dx_') ||
      intentId.contains('diagnosis') ||
      intentId.contains('differential')) {
    return ClinicalPhase.synthesis;
  }
  if (intentId.startsWith('mx_') ||
      intentId.contains('manage') ||
      intentId.contains('treat')) {
    return ClinicalPhase.management;
  }
  if (intentId.startsWith('meta_') || intentId == 'consistency_check') {
    return ClinicalPhase.meta;
  }
  return ClinicalPhase.history;
}

/// Detect phase from student language (before intent lock).
ClinicalPhase detectPhase(String normText) {
  if (RegExp(
    r'\b(examin|inspect|palpat|percuss|auscult|listen to|look at the|feel the|check the chest|check the abdomen|neurolog|glasgow|capillary refill)\b',
    caseSensitive: false,
  ).hasMatch(normText)) {
    return ClinicalPhase.examination;
  }
  if (RegExp(
    r'\b(order|request|i want a|send for|fbc|cbc|lft|ue|electrolyte|x[- ]?ray|cxr|ultrasound|scan|mri|ct |blood culture|rdt|malaria test|lp\b|lumbar)\b',
    caseSensitive: false,
  ).hasMatch(normText)) {
    return ClinicalPhase.investigation;
  }
  if (RegExp(
    r'\b(i think (it|this) is|my (working )?diagnosis|differential|most likely|impression is|could this be)\b',
    caseSensitive: false,
  ).hasMatch(normText)) {
    return ClinicalPhase.synthesis;
  }
  if (RegExp(
    r'\b(manage|treatment|treat with|start on|prescribe|admit|discharge plan)\b',
    caseSensitive: false,
  ).hasMatch(normText)) {
    return ClinicalPhase.management;
  }
  return ClinicalPhase.history;
}

enum SpeechAct {
  question,
  command,
  statement,
  diagnosisClaim,
  reassurance,
}

SpeechAct detectSpeechAct(String normText) {
  if (RegExp(
    r'\b(i think|diagnosis|differential|most likely|impression)\b',
    caseSensitive: false,
  ).hasMatch(normText)) {
    return SpeechAct.diagnosisClaim;
  }
  if (RegExp(
    r'^(please |kindly )?(examin|order|request|start|give|check|do a)\b',
    caseSensitive: false,
  ).hasMatch(normText.trim())) {
    return SpeechAct.command;
  }
  if (RegExp(
    r'\b(don.?t worry|you.?ll be fine|it.?s okay)\b',
    caseSensitive: false,
  ).hasMatch(normText)) {
    return SpeechAct.reassurance;
  }
  if (normText.contains('?') ||
      RegExp(
        r'^(do|did|does|is|are|have|has|was|were|any|can|could|will|what|when|where|why|how|tell|describe)\b',
        caseSensitive: false,
      ).hasMatch(normText.trim())) {
    return SpeechAct.question;
  }
  return SpeechAct.statement;
}

/// CLER clinical reasoning engine — pure Dart (Flutter-safe)
/// Port of ClerkAI Worker Suite v2.2 offline patient simulator.

import 'dart:math';

import 'case_schema.dart';
import 'register_sensor.dart';
import 'reply_rules.dart';
import 'dialogue_state.dart';
import 'intent_patterns.dart';
import 'miss_log.dart';
import 'move_decision.dart';
import 'ontology.dart';
import 'safety.dart';
import 'scorer.dart';
import 'soft_match.dart';

// ─── UPGRADE 1 — TEXT NORMALISATION ────────────────────────────────────────

final List<(RegExp, String)> normalisationMap = [
  (RegExp(r'\bbody dey hot\b', caseSensitive: false), 'fever temperature'),
  (RegExp(r'\bbody hot\b', caseSensitive: false), 'fever temperature'),
  (RegExp(r'\bpikin\b', caseSensitive: false), 'child'),
  (RegExp(r'\bbaby dey move\b', caseSensitive: false), 'fetal movement'),
  (RegExp(r'\bno dey move\b', caseSensitive: false), 'not moving'),
  (RegExp(r'\bwetin dey worry\b', caseSensitive: false), 'what is wrong presenting complaint'),
  (RegExp(r'\banka.*swollen\b', caseSensitive: false), 'ankle swelling oedema'),
  (RegExp(r'\bleg.*swell\b', caseSensitive: false), 'leg swelling oedema'),
  (RegExp(r'\bhead dey pain\b', caseSensitive: false), 'headache'),
  (RegExp(r'\bstomach dey pain\b', caseSensitive: false), 'abdominal pain'),
  (RegExp(r'\bchest dey pain\b', caseSensitive: false), 'chest pain'),
  (RegExp(r'\bbreath dey hard\b', caseSensitive: false), 'difficulty breathing dyspnoea'),
  (RegExp(r'\bdey shake\b', caseSensitive: false), 'shaking seizure convulsion'),
  (RegExp(r'\bno gree wake\b', caseSensitive: false), 'not waking altered consciousness'),
  (RegExp(r'\bchop vomit\b', caseSensitive: false), 'vomiting nausea'),
  (RegExp(r'\bh\/o\b', caseSensitive: false), 'history of'),
  (RegExp(r'\bc\/o\b', caseSensitive: false), 'complaining of'),
  (RegExp(r'\bk\/a\b', caseSensitive: false), 'known allergic'),
  (RegExp(r'\bk\/c\/o\b', caseSensitive: false), 'known case of'),
  (RegExp(r'\bpm hx\b', caseSensitive: false), 'past medical history'),
  (RegExp(r'\bpmhx\b', caseSensitive: false), 'past medical history'),
  (RegExp(r'\bfhx\b', caseSensitive: false), 'family history'),
  (RegExp(r'\bshx\b', caseSensitive: false), 'social history'),
  (RegExp(r'\bhpc\b', caseSensitive: false), 'history presenting complaint'),
  (RegExp(r'\bbp\b', caseSensitive: false), 'blood pressure'),
  (RegExp(r'\bhr\b', caseSensitive: false), 'heart rate pulse'),
  (RegExp(r'\brr\b', caseSensitive: false), 'respiratory rate breathing'),
  (RegExp(r'\bspo2\b', caseSensitive: false), 'oxygen saturation spo2'),
  (RegExp(r'\bo2 sat\b', caseSensitive: false), 'oxygen saturation'),
  (RegExp(r'\btemp\b', caseSensitive: false), 'temperature'),
  (RegExp(r'\bwt\b', caseSensitive: false), 'weight'),
  (RegExp(r'\bht\b', caseSensitive: false), 'height'),
  (RegExp(r'\blocsn\b', caseSensitive: false), 'loss of consciousness'),
  (RegExp(r'\bloc\b', caseSensitive: false), 'level of consciousness'),
  (RegExp(r'\bsob\b', caseSensitive: false), 'shortness of breath dyspnoea'),
  (RegExp(r'\bdob\b', caseSensitive: false), 'difficulty breathing'),
  (RegExp(r'\bpnd\b', caseSensitive: false), 'paroxysmal nocturnal dyspnoea orthopnoea'),
  (RegExp(r'\bjvp\b', caseSensitive: false), 'jugular venous pressure'),
  (RegExp(r'\bpv\b', caseSensitive: false), 'per vaginum vaginal'),
  (RegExp(r'\bfc\b', caseSensitive: false), 'febrile convulsion seizure'),
  (RegExp(r'\bneonatal\b', caseSensitive: false), 'newborn neonate neonatal'),
  (RegExp(r'\bga\b', caseSensitive: false), 'gestational age weeks'),
  (RegExp(r'\bga(\d+)\b', caseSensitive: false), 'gestation \$1 weeks'),
  (RegExp(r'\bimci\b', caseSensitive: false), 'integrated management childhood illness assessment'),
  (RegExp(r'\bcmam\b', caseSensitive: false), 'community management acute malnutrition'),
  (RegExp(r'\bmuac\b', caseSensitive: false), 'mid upper arm circumference malnutrition'),
  (RegExp(r'\brutf\b', caseSensitive: false), 'ready use therapeutic food malnutrition'),
  (RegExp(r'\bsam\b', caseSensitive: false), 'severe acute malnutrition'),
  (RegExp(r'\bmam\b', caseSensitive: false), 'moderate acute malnutrition'),
  (RegExp(r'\bepi\b', caseSensitive: false), 'expanded programme immunisation vaccination'),
  (RegExp(r'\bwho\b', caseSensitive: false), 'world health organisation protocol'),
  (RegExp(r'\buac\b', caseSensitive: false), 'mid upper arm circumference'),
  (RegExp(r'\bfeva\b', caseSensitive: false), 'fever'),
  (RegExp(r'\bvomitting\b', caseSensitive: false), 'vomiting'),
  (RegExp(r'\bsiezure\b', caseSensitive: false), 'seizure'),
  (RegExp(r'\bconvultion\b', caseSensitive: false), 'convulsion'),
  (RegExp(r'\bjoundice\b', caseSensitive: false), 'jaundice'),
  (RegExp(r'\bbreathless\b', caseSensitive: false), 'shortness of breath dyspnoea'),
  (RegExp(r'\bswolen\b', caseSensitive: false), 'swollen'),
  (RegExp(r'\bpallor\b', caseSensitive: false), 'pallor anaemia pale'),
  (RegExp(r'\bdehydrat\b', caseSensitive: false), 'dehydration'),
  (RegExp(r'\bwt loss\b', caseSensitive: false), 'weight loss'),
  (RegExp(r'\btachycardi\b', caseSensitive: false), 'tachycardia fast heart rate'),
  (RegExp(r'\bbradycardi\b', caseSensitive: false), 'bradycardia slow heart rate'),
];

String normaliseText(String raw) {
  var t = raw.toLowerCase().trim();
  for (final (pattern, replacement) in normalisationMap) {
    t = t.replaceAllMapped(pattern, (m) {
      var rep = replacement;
      if (m.groupCount >= 1 && m.group(1) != null) {
        rep = rep.replaceAll(r'$1', m.group(1)!);
      }
      return rep;
    });
  }
  t = t.replaceAll(RegExp(r"[^\w\s'-]"), ' ').replaceAll(RegExp(r'\s{2,}'), ' ').trim();
  return t;
}

// ─── UPGRADE 2 — INTENT CLUSTERING ─────────────────────────────────────────

const Map<String, List<String>> intentClusters = {
  'full_history': ['hpc_onset', 'hpc_character', 'hpc_radiation', 'hpc_relieving', 'hpc_triggers', 'hpc_associated'],
  'social_cluster': ['shx_general', 'shx_travel', 'fhx_general'],
  'obstetric_cluster': ['parity', 'antenatal', 'sr_fetal_movement', 'sr_abdominal'],
  'paediatric_hx': ['immunisation', 'pmh_general', 'shx_travel', 'sr_fever', 'sr_seizures', 'birth_history', 'maternal_history', 'feeding_history'],
  'respiratory_hx': ['hpc_character', 'hpc_triggers', 'sr_fever', 'pmh_general', 'meds_general', 'fhx_general'],
  'general_exam': ['exam_general', 'exam_skin'],
  'full_exam': ['exam_general', 'exam_cardiovascular', 'exam_chest', 'exam_abdomen', 'exam_neuro', 'exam_skin'],
  'neuro_cluster': ['exam_neuro', 'exam_general', 'sr_consciousness', 'sr_seizures'],
  'cardiac_cluster': ['exam_cardiovascular', 'exam_general', 'sr_chest_pain', 'sr_oedema'],
  'abdo_cluster': ['exam_abdomen', 'exam_specific_signs', 'exam_general'],
  'baseline_ix': ['ix_fbc', 'ix_lft', 'ix_crp', 'ix_urinalysis'],
  'malaria_ix': ['ix_rdt', 'ix_thickfilm', 'ix_fbc', 'ix_lft'],
  'cardiac_ix': ['ix_ecg', 'ix_cxr', 'ix_fbc', 'ix_lft'],
  'respiratory_ix': ['ix_cxr', 'ix_pefr', 'ix_abg', 'ix_fbc'],
};

class ClusterTrigger {
  final List<String> phrases;
  final List<String> clusters;
  const ClusterTrigger({required this.phrases, required this.clusters});
}

const List<ClusterTrigger> clusterTriggers = [
  ClusterTrigger(phrases: ['take a full history', 'full history', 'complete history', 'take history'], clusters: ['full_history', 'social_cluster']),
  ClusterTrigger(phrases: ['social history', 'any social history'], clusters: ['social_cluster']),
  ClusterTrigger(phrases: ['obstetric history', 'antenatal history', 'any pregnancies'], clusters: ['obstetric_cluster']),
  ClusterTrigger(phrases: ['paediatric history', 'child history'], clusters: ['paediatric_hx']),
  ClusterTrigger(phrases: ['respiratory history', 'breathing history'], clusters: ['respiratory_hx']),
  ClusterTrigger(phrases: ['general examination', 'general survey', 'examine generally', 'examine the patient'], clusters: ['general_exam']),
  ClusterTrigger(phrases: ['full examination', 'complete examination', 'examine from head to toe'], clusters: ['full_exam']),
  ClusterTrigger(phrases: ['neurological examination', 'examine neurologically', 'check neurology'], clusters: ['neuro_cluster']),
  ClusterTrigger(phrases: ['cardiac examination', 'cardiovascular examination', 'examine heart'], clusters: ['cardiac_cluster']),
  ClusterTrigger(phrases: ['abdominal examination', 'examine the abdomen', 'abdominal exam'], clusters: ['abdo_cluster']),
  ClusterTrigger(phrases: ['baseline investigations', 'routine bloods', 'routine investigations', 'basic bloods'], clusters: ['baseline_ix']),
  ClusterTrigger(phrases: ['malaria workup', 'malaria investigations', 'test for malaria'], clusters: ['malaria_ix']),
  ClusterTrigger(phrases: ['cardiac workup', 'heart investigations'], clusters: ['cardiac_ix']),
  ClusterTrigger(phrases: ['respiratory investigations', 'breathing tests', 'lung investigations'], clusters: ['respiratory_ix']),
  ClusterTrigger(phrases: ['birth history', 'delivery history', 'how was baby born', 'any birth complications', 'neonatal history', 'perinatal history'], clusters: ['paediatric_hx']),
  ClusterTrigger(phrases: ['maternal history', 'antenatal history', 'pregnancy history', 'obstetric history', 'any antenatal problems'], clusters: ['obstetric_cluster', 'paediatric_hx']),
];

List<String> resolveClusterIntents(String normText, Map<String, dynamic> caseData) {
  final hits = <String>{};
  final intentMap = caseData['intentMap'] as Map<String, dynamic>?;
  if (intentMap == null) return [];
  for (final trigger in clusterTriggers) {
    if (trigger.phrases.any((ph) => normText.contains(ph))) {
      for (final clusterName in trigger.clusters) {
        for (final id in intentClusters[clusterName] ?? []) {
          if (intentMap.containsKey(id)) hits.add(id);
        }
      }
    }
  }
  return hits.toList();
}

// ─── UPGRADE 3 — PERSONALITY ───────────────────────────────────────────────

const Map<String, Map<String, dynamic>> temperaments = {
  'stoic': {'style': 'brief', 'prefixes': ['...', 'Well...', 'I suppose...'], 'suffixes': ['.', '... that\'s about it.'], 'distressMod': 0.3},
  'anxious': {'style': 'verbose', 'prefixes': ['Oh doctor...', 'I\'m so worried...', 'Please help...'], 'suffixes': ['... is that serious?', '... what does it mean?'], 'distressMod': 1.4},
  'open': {'style': 'normal', 'prefixes': ['Sure...', 'Of course...', 'Yes...'], 'suffixes': ['.', '.'], 'distressMod': 1.0},
  'reticent': {'style': 'brief', 'prefixes': ['...', 'Hmm...', 'Not sure...'], 'suffixes': ['.', '... I don\'t know.'], 'distressMod': 0.5},
  'chatty': {'style': 'verbose', 'prefixes': ['Well you know...', 'Actually...', 'Funny thing...'], 'suffixes': ['... you know what I mean?', '... anyway.'], 'distressMod': 0.8},
};

String assignTemperament(Map<String, dynamic>? patient) {
  if (patient == null) return 'open';
  final seed = (patient['name'] as String? ?? patient['id'] as String? ?? 'default').hashCode;
  final keys = temperaments.keys.toList();
  return keys[seed.abs() % keys.length];
}

String applyPersonality(String baseText, String temperament, bool isDistressed, Random rng) {
  if (baseText.isEmpty) return baseText;
  final temp = temperaments[temperament] ?? temperaments['open']!;
  final prefixes = (temp['prefixes'] as List).cast<String>();
  final suffixes = (temp['suffixes'] as List).cast<String>();
  var result = baseText;
  if (rng.nextDouble() < 0.4) result = '${prefixes[rng.nextInt(prefixes.length)]} $result';
  if (isDistressed && rng.nextDouble() < (temp['distressMod'] as num)) {
    result = '$result ${suffixes[rng.nextInt(suffixes.length)]}';
  }
  return result.trim();
}

// ─── UPGRADE 5 — REPLY SCOPE ───────────────────────────────────────────────

bool isClosedQuestion(String normText) {
  return RegExp(r'^(do|did|does|is|are|has|have|was|were|any|can|could|will|would)\b', caseSensitive: false).hasMatch(normText.trim());
}

String capPatientReply(String text, String normText) {
  if (text.isEmpty) return text;
  final sentences = RegExp(r'[^.!?]+[.!?]+(?:\s|$)').allMatches(text).map((m) => m.group(0)!).toList();
  if (sentences.isEmpty || sentences.length <= 1) return text.trim();
  if (isClosedQuestion(normText)) return sentences[0].trim();
  return sentences.take(2).join('').trim();
}

const Set<String> distressIntents = {
  'sr_seizures', 'sr_consciousness', 'sr_chest_pain', 'sr_fetal_movement',
  'hpc_character', 'exam_neuro', 'exam_general',
};

// ─── 2. DANGER PATTERNS + INTENT CLASSIFICATION ────────────────────────────

class DangerHit {
  final String explanation;
  final int penalty;
  DangerHit({required this.explanation, required this.penalty});
}

final List<Map<String, dynamic>> globalDangerousPatterns = [
  {
    'pattern': RegExp(r'\baspirin\b', caseSensitive: false),
    'penalty': 20,
    'explanation': '⛔ Aspirin is contraindicated in children under 16 years (Reye\'s syndrome risk) and should be avoided in febrile illnesses. Deducted −20 pts.',
  },
  {
    'pattern': RegExp(r'\bchloroquine\b', caseSensitive: false),
    'penalty': 15,
    'explanation': '⚠️ Chloroquine-resistant P. falciparum is widespread in Nigeria. First-line for severe malaria is IV artesunate (WHO/FMOH guidelines). Deducted −15 pts.',
  },
  {
    'pattern': RegExp(r'\bbeta.?blocker|propranolol|atenolol\b', caseSensitive: false),
    'penalty': 20,
    'explanation': '⛔ Beta-blockers are absolutely contraindicated in acute asthma — they cause life-threatening bronchospasm. Deducted −20 pts.',
  },
  {
    'pattern': RegExp(r'\bnsaid|ibuprofen|diclofenac\b', caseSensitive: false),
    'penalty': 15,
    'explanation': '⛔ NSAIDs are contraindicated in surgical abdomens (mask peritoneal signs), pregnancy >20 weeks (renal/ductus effects), and active heart failure. Deducted −15 pts.',
  },
  {
    'pattern': RegExp(r'\bace.?inhibitor|lisinopril|enalapril|ramipril\b', caseSensitive: false),
    'penalty': 15,
    'explanation': '⛔ ACE inhibitors are teratogenic in the 2nd and 3rd trimesters and are absolutely contraindicated in pregnancy. Deducted −15 pts.',
  },
  {
    'pattern': RegExp(r'\blumbar.?puncture.{0,20}without|lp.{0,20}before.{0,20}stabili', caseSensitive: false),
    'penalty': 15,
    'explanation': '⚠️ LP should only be performed after stabilising the patient and excluding raised ICP (papilloedema, focal neurology). Deducted −15 pts.',
  },
  {
    'pattern': RegExp(r'\bsedati|diazepam.{0,20}asthma|lorazepam.{0,20}respir', caseSensitive: false),
    'penalty': 15,
    'explanation': '⛔ Sedation in a patient with acute respiratory distress can cause respiratory arrest. Contraindicated in acute asthma and any unprotected airway. Deducted −15 pts.',
  },
];

DangerHit? checkDanger(String normText, Map<String, dynamic> caseData) {
  final traps = caseData['trapActions'] as List?;
  if (traps != null) {
    for (final trap in traps) {
      final t = Map<String, dynamic>.from(trap as Map);
      // pattern may be a string or already RegExp in Dart port
      final pat = t['pattern'];
      RegExp re;
      if (pat is RegExp) {
        re = pat;
      } else if (pat is String) {
        re = RegExp(pat, caseSensitive: false);
      } else {
        continue;
      }
      if (re.hasMatch(normText)) {
        return DangerHit(
          explanation: t['explanation'] as String? ?? 'Dangerous action',
          penalty: (t['penalty'] as num?)?.toInt() ?? 10,
        );
      }
    }
  }
  for (final g in globalDangerousPatterns) {
    if ((g['pattern'] as RegExp).hasMatch(normText)) {
      return DangerHit(
        explanation: g['explanation'] as String,
        penalty: g['penalty'] as int,
      );
    }
  }
  return null;
}

const Set<String> singleWordBoosts = {
  'delivery', 'labour', 'labor', 'seizure', 'jaundice', 'pallor', 'fever',
  'vomiting', 'rash', 'cough', 'wheeze', 'immunisation', 'immunization',
  'vaccination', 'breastfeeding', 'feeding', 'birth', 'gestation', 'pregnancy',
  'convulsion', 'fit', 'swelling', 'oedema', 'edema', 'diarrhoea', 'diarrhea',
  'constipation', 'appetite', 'weight', 'bleeding', 'discharge', 'pain',
  'headache', 'breathless', 'dyspnoea', 'palpitation', 'syncope', 'collapse',
  'allergy', 'allergies', 'medication', 'medications', 'surgery', 'admission',
  'malaria', 'tuberculosis', 'hiv', 'diabetes', 'hypertension', 'asthma',
  'epilepsy', 'sickle', 'anaemia', 'anemia', 'dehydration', 'travel',
  'occupation', 'smoking', 'alcohol',
};

/// Returns the best matching pattern map or null.
Map<String, dynamic>? classifyIntent(String normText, List<Map<String, dynamic>> patterns) {
  final scored = <Map<String, dynamic>>[];

  for (final pattern in patterns) {
    var score = 0;
    var phraseHit = false;

    for (final phrase in (pattern['phrases'] as List? ?? []).cast<String>()) {
      if (normText.contains(phrase.toLowerCase())) {
        score += 30;
        phraseHit = true;
      }
    }

    var keywordHits = 0;
    for (final kw in (pattern['keywords'] as List? ?? []).cast<String>()) {
      final kwLower = kw.toLowerCase();
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
    if (keywordHits >= 2) score += 10;
    if (keywordHits >= 4) score += 10;

    if (score > 0) {
      scored.add({'pattern': pattern, 'score': score, 'phraseHit': phraseHit});
    }
  }

  if (scored.isEmpty) return null;
  scored.sort((a, b) => (b['score'] as int).compareTo(a['score'] as int));
  final best = scored[0];
  final second = scored.length > 1 ? scored[1] : null;

  final inputWords = normText.trim().split(RegExp(r'\s+'));
  if (inputWords.length <= 3) {
    for (final w in inputWords) {
      if (singleWordBoosts.contains(w.toLowerCase())) {
        best['score'] = (best['score'] as int) + 15;
        break;
      }
    }
  }

  if ((best['score'] as int) < 20) return null;
  if (best['phraseHit'] == true) return best['pattern'] as Map<String, dynamic>;

  if (second != null && ((best['score'] as int) - (second['score'] as int)) < 25) {
    return null; // ambiguous
  }
  return best['pattern'] as Map<String, dynamic>;
}


// ─── CONSISTENCY CHECK ─────────────────────────────────────────────────────

const List<String> followupKeywords = [
  'again', 'still', 'how long', 'when did', 'duration', 'same', 'confirm',
  'you said', 'earlier', 'before', 'previously',
];

String? checkConsistency(String normText, List conversationHistory) {
  if (!followupKeywords.any((kw) => normText.contains(kw))) return null;
  if (conversationHistory.length < 2) return null;

  final durationPattern = RegExp(r'(\d+)\s*(day|days|week|weeks|month|months|year|years)', caseSensitive: false);

  for (final turn in conversationHistory.reversed) {
    if (turn is! Map) continue;
    if (turn['role'] != 'assistant' && turn['role'] != 'patient') continue;
    final content = turn['content'] as String? ?? turn['reply'] as String? ?? '';
    final matches = durationPattern.allMatches(content);
    if (matches.isNotEmpty) {
      return 'As I said doctor, ${matches.first.group(0)} now.';
    }
  }
  return null;
}

// ─── HIDDEN FACTS ──────────────────────────────────────────────────────────

Map<String, dynamic>? resolveHiddenFact(String normText, Map<String, dynamic> caseData, List<String> askedIntents) {
  final hiddenFacts = caseData['hidden_facts'] as Map<String, dynamic>?;
  if (hiddenFacts == null) return null;

  const triggers = {
    'maternal_blood_group': ['blood group', 'blood type', 'rhesus', 'abo'],
    'g6pd_status': ['g6pd', 'enzyme', 'haemolysis', 'deficiency'],
    'family_seizure_history': ['family', 'anyone else', 'relative', 'sibling', 'parent', 'father', 'mother'],
    'developmental_history': ['development', 'milestone', 'walking', 'talking', 'sitting'],
    'tb_contact': ['contact', 'neighbour', 'cough', 'tuberculosis', 'tb', 'anyone coughing'],
    'hiv_status': ['hiv', 'aids', 'retroviral', 'positive', 'status'],
    'feeding_history': ['breastfeed', 'breast feed', 'formula', 'weaning', 'feeding'],
    'socioeconomic_status': ['work', 'job', 'income', 'afford', 'money', 'occupation'],
    'steroid_response': ['previous episode', 'before', 'happened before', 'recurrence', 'again'],
    'family_renal_history': ['family', 'kidney', 'relative', 'dialysis', 'renal'],
  };

  for (final entry in triggers.entries) {
    final factKey = entry.key;
    if (!hiddenFacts.containsKey(factKey)) continue;
    if (!entry.value.any((t) => normText.contains(t))) continue;

    final fact = Map<String, dynamic>.from(hiddenFacts[factKey] as Map);
    final unlockConditions = (fact['unlock_conditions'] as List?)?.cast<String>() ?? [];
    final unlocked = unlockConditions.isEmpty || unlockConditions.any(askedIntents.contains);

    return {
      'factKey': factKey,
      'unlocked': unlocked,
      'response': unlocked ? fact['unlocked_response'] : fact['locked_response'],
    };
  }
  return null;
}

// ─── NEGATIVE / FALLBACK / N/A GENERATORS ──────────────────────────────────

final List<Map<String, dynamic>> negativeReplyMap = [
  {'keywords': ['fever', 'temperature', 'hot', 'pyrexia', 'febrile'], 'reply': (String p) => '${p}No doctor, no fever. I have not been feeling hot.'},
  {'keywords': ['cough', 'coughing'], 'reply': (String p) => '${p}No doctor, no cough at all.'},
  {'keywords': ['wheeze', 'wheezing', 'whistling'], 'reply': (String p) => '${p}No doctor, no whistling sound from the chest.'},
  {'keywords': ['vomit', 'vomiting', 'nausea', 'throw up'], 'reply': (String p) => '${p}No doctor, no vomiting.'},
  {'keywords': ['diarrhoea', 'diarrhea', 'loose stool', 'watery stool'], 'reply': (String p) => '${p}No doctor, no diarrhoea. Stool has been normal.'},
  {'keywords': ['convuls', 'seizure', 'fit', 'shaking', 'jerking'], 'reply': (String p) => '${p}No doctor, no convulsion or fit.'},
  {'keywords': ['rash', 'skin', 'itching', 'itch'], 'reply': (String p) => '${p}No doctor, no rash or skin problem.'},
  {'keywords': ['bleed', 'bleeding', 'blood'], 'reply': (String p) => '${p}No doctor, no bleeding anywhere.'},
  {'keywords': ['headache', 'head pain', 'head ache'], 'reply': (String p) => '${p}No doctor, no headache.'},
  {'keywords': ['chest pain', 'chest discomfort'], 'reply': (String p) => '${p}No doctor, no chest pain.'},
  {'keywords': ['palpitation', 'heart beat', 'heart racing', 'fast heart'], 'reply': (String p) => '${p}No doctor, I have not noticed my heart beating fast.'},
  {'keywords': ['sweat', 'sweating', 'perspir'], 'reply': (String p) => '${p}No doctor, no excessive sweating.'},
  {'keywords': ['weight loss', 'losing weight', 'weight drop'], 'reply': (String p) => '${p}No doctor, weight has been stable as far as I know.'},
  {'keywords': ['appetite', 'eating', 'food', 'hungry'], 'reply': (String p) => '${p}My appetite has been okay, eating normally.'},
  {'keywords': ['urine', 'urinating', 'urination', 'pee', 'passing urine'], 'reply': (String p) => '${p}No doctor, urine has been normal — no pain or burning.'},
  {'keywords': ['stool', 'bowel', 'constipat'], 'reply': (String p) => '${p}No doctor, bowels have been moving normally.'},
  {'keywords': ['drool', 'drooling'], 'reply': (String p) => '${p}No doctor, no drooling.'},
  {'keywords': ['walk', 'walking', 'movement', 'mobility'], 'reply': (String p) => '${p}Yes doctor, walking normally with no problem.'},
  {'keywords': ['neck stiff', 'neck pain', 'stiff neck'], 'reply': (String p) => '${p}No doctor, no neck stiffness or pain.'},
  {'keywords': ['ear', 'hearing', 'earache'], 'reply': (String p) => '${p}No doctor, no ear pain or hearing problem.'},
  {'keywords': ['eye', 'vision', 'seeing', 'sight'], 'reply': (String p) => '${p}No doctor, no eye or vision problem.'},
];

String generateNegativeReply(String normText, Map<String, dynamic> caseData) {
  final patient = caseData['patient'] as Map<String, dynamic>?;
  final age = patient?['age'];
  final isProxy = age is num && age < 5;
  final prefix = isProxy ? '(Mother) ' : '';
  for (final entry in negativeReplyMap) {
    final kws = (entry['keywords'] as List).cast<String>();
    if (kws.any((k) => normText.contains(k))) {
      final fn = entry['reply'] as String Function(String);
      return fn(prefix);
    }
  }
  return '${prefix}No doctor, I haven\'t noticed that.';
}

String generateFallback(String normText, Map<String, dynamic> caseData, List history) {
  if (RegExp(r'\b(hello|hi|good morning|good afternoon)\b', caseSensitive: false).hasMatch(normText)) {
    return 'Please go ahead, doctor.';
  }
  const responses = [
    'I\'m not sure I understand that, doctor.',
    'Sorry doctor, I didn\'t quite follow that question.',
    'Could you rephrase that, doctor?',
    'I\'m not sure what you mean, doctor.',
    'I didn\'t understand that question, doctor.',
  ];
  return responses[history.length % responses.length];
}

String generateNotApplicable(String intentId, Map<String, dynamic> caseData) {
  final patient = caseData['patient'] as Map<String, dynamic>?;
  final age = patient?['age'];
  final sex = patient?['sex'] as String? ?? 'Unknown';
  final na = <String, String>{
    'sr_fever': 'No, I haven\'t had any fever or chills.',
    'sr_nausea': 'No nausea or vomiting.',
    'sr_seizures': 'No, no fits or seizures.',
    'sr_chest_pain': 'No chest pain.',
    'sr_jaundice': 'No, my eyes haven\'t been yellow and my urine has been normal.',
    'shx_travel': 'No, I haven\'t travelled anywhere recently.',
    'shx_general': 'I\'m ${sex == 'Female' ? 'a housewife' : 'working in my usual occupation'}. I don\'t smoke. I drink occasionally.',
    'fhx_general': 'No notable family history of serious illness.',
    'allergies_general': 'No known drug allergies.',
    'parity': sex == 'Male' ? 'That\'s not applicable — I\'m a $age-year-old male patient.' : 'This is my first pregnancy.',
    'antenatal': sex == 'Male' ? 'That\'s not applicable to me.' : 'I\'ve been attending antenatal clinic.',
    'sr_abdominal': 'No significant abdominal pain.',
    'sr_oedema': 'No notable swelling.',
    'sr_urinary': 'Urine is normal — no burning or frequency.',
    'sr_bowels': 'My bowels have been normal.',
    'sr_appetite': 'My appetite has been okay.',
    'sr_consciousness': 'I\'ve been alert and conscious throughout.',
    'sr_fetal_movement': sex == 'Male' ? 'That\'s not applicable.' : 'Yes, baby has been moving normally.',
    'immunisation': 'Up to date with vaccinations as far as I know.',
  };
  return na[intentId] ?? 'No, that\'s not something I\'ve noticed or experienced.';
}


// ─── PEARL LOOKUP ──────────────────────────────────────────────────────────

const Map<String, Map<String, String>> builtinPearls = {
  'hpc_onset': {
    '_default': 'Always establish the exact timing and mode of onset — sudden (vascular, obstructive) vs gradual (inflammatory, neoplastic) onset has strong diagnostic value.',
    'neonatal jaundice (physiological)': 'In physiological jaundice, onset is after 24 hours of life, peaks day 3–4 in term infants, and resolves by day 7–10. Onset before 24h is always pathological.',
  },
  'birth_history': {
    '_default': 'Birth history (GA, mode, Apgar, resuscitation) is essential in any neonatal presentation.',
  },
  'feeding_history': {
    '_default': 'In jaundice, ask about feeding frequency and urine/stool colour — poor intake and pale stools raise concern for pathological causes.',
  },
  'ix_bilirubin': {
    '_default': 'Plot bilirubin on the appropriate nomogram (NICE / AAP) and act on the treatment threshold for the baby\'s age in hours.',
  },
};

String? getPearl(String intentId, String? diagnosisPrimary) {
  final bank = builtinPearls[intentId];
  if (bank == null) return null;
  if (diagnosisPrimary != null) {
    final key = diagnosisPrimary.toLowerCase();
    if (bank.containsKey(key)) return bank[key];
  }
  return bank['_default'];
}



/// Result of processing a student message against a case.
class ChatResult {
  final String reply;
  final String? intentId;
  final String type;
  final bool isDangerous;
  final int score;
  final int? penalty;
  final String? pearl;
  final String normalisedText;
  final String? temperamentApplied;
  final List<Map<String, dynamic>>? clusterIntents;
  final String? hiddenFact;
  final bool? unlocked;
  final List<String>? matchedIntentIds;
  final double? confidence;
  final String? matchSource;
  final String? phase;
  final List<String>? validationWarnings;
  final String? ruleMatched;

  const ChatResult({
    required this.reply,
    this.intentId,
    required this.type,
    this.isDangerous = false,
    this.score = 0,
    this.penalty,
    this.pearl,
    required this.normalisedText,
    this.temperamentApplied,
    this.clusterIntents,
    this.hiddenFact,
    this.unlocked,
    this.matchedIntentIds,
    this.confidence,
    this.matchSource,
    this.phase,
    this.validationWarnings,
    this.ruleMatched,
  });

  Map<String, dynamic> toJson() => {
        'reply': reply,
        'intentId': intentId,
        'type': type,
        'isDangerous': isDangerous,
        'score': score,
        if (penalty != null) 'penalty': penalty,
        if (pearl != null) 'pearl': pearl,
        'normalisedText': normalisedText,
        if (temperamentApplied != null) 'temperamentApplied': temperamentApplied,
        if (clusterIntents != null) 'clusterIntents': clusterIntents,
        if (hiddenFact != null) 'hiddenFact': hiddenFact,
        if (unlocked != null) 'unlocked': unlocked,
        if (matchedIntentIds != null) 'matchedIntentIds': matchedIntentIds,
        if (confidence != null) 'confidence': confidence,
        if (matchSource != null) 'matchSource': matchSource,
        if (phase != null) 'phase': phase,
        if (ruleMatched != null) 'ruleMatched': ruleMatched,
      };
}

/// Resolve patient line (rules → fallback) then apply reply-length cap.
({String text, String ruleMatched}) patientReplyText(
  Map<String, dynamic> entry,
  String normText, {
  required DialogueState state,
  required String intentId,
  required Register register,
  int? priorAskCount,
}) {
  final resolved = resolveReplyText(
    intentEntry: entry,
    state: state,
    currentIntentId: intentId,
    register: register,
    priorAskCount: priorAskCount,
  );
  return (
    text: capPatientReply(resolved.text, normText),
    ruleMatched: resolved.ruleMatched,
  );
}

String enrichVoice(
  String text,
  String temperament,
  bool isDistressed,
  Random rng, {
  bool isProxy = false,
}) {
  if (text.isEmpty) return text;
  var result = applyPersonality(text, temperament, isDistressed, rng);
  if (rng.nextDouble() < 0.12) {
    final fillers = isProxy
        ? ['Let me think…', 'From what I remember…']
        : ['Let me think…', 'Hmm…'];
    result = '${fillers[rng.nextInt(fillers.length)]} $result';
  }
  return result.trim();
}

String confusedPatient(Map<String, dynamic> caseData) {
  final patient = caseData['patient'] as Map<String, dynamic>?;
  final age = patient?['age'];
  final isProxy = age is num && age < 5;
  final prefix = isProxy ? '(Mother) ' : '';
  return '${prefix}Sorry doctor, I\'m not sure I follow. Could you ask that another way?';
}

String plainUnsure(Map<String, dynamic> caseData) {
  final patient = caseData['patient'] as Map<String, dynamic>?;
  final age = patient?['age'];
  final isProxy = age is num && age < 5;
  final prefix = isProxy ? '(Mother) ' : '';
  return '${prefix}I\'m not sure about that, doctor.';
}

/// Core turn processor — Phases 1–6 architecture.
ChatResult processChat({
  required Map<String, dynamic> caseData,
  required String message,
  List conversationHistory = const [],
  List<String> askedIntents = const [],
  DialogueState? dialogue,
  bool validateCaseSchema = false,
}) {
  final state = dialogue ?? DialogueState();
  final normText = normaliseText(message);
  final rng = Random();
  state.noteStudent(normText);
  final register = classifyRegister(normText);

  List<String>? schemaWarnings;
  if (validateCaseSchema) {
    final v = validateCase(caseData);
    if (!v.ok) {
      return ChatResult(
        reply: 'Case configuration error.',
        type: 'schema_error',
        normalisedText: normText,
        validationWarnings: v.errors,
      );
    }
    schemaWarnings = v.warnings.isEmpty ? null : v.warnings;
  }

  final caseId = caseData['caseId'] as String? ?? 'unknown';
  final patient = caseData['patient'] as Map<String, dynamic>?;
  final temperament = assignTemperament(patient);
  final age = patient?['age'];
  final isProxy = age is num && age < 5;
  final scoringMap = caseData['scoringMap'] as Map<String, dynamic>? ?? {};
  final intentMap = caseData['intentMap'] as Map<String, dynamic>? ?? {};
  final diagnosis = caseData['diagnosis'] as Map<String, dynamic>?;

  // ── Phase 4: Safety ─────────────────────────────────────────────────────
  final safety = evaluateSafety(normText, caseData);
  if (safety != null) {
    return ChatResult(
      reply: safety.explanation,
      type: 'penalty',
      isDangerous: true,
      penalty: safety.penalty,
      score: 0,
      normalisedText: normText,
      matchSource: safety.source,
    );
  }

  // ── Consistency (slot-aware) ────────────────────────────────────────────
  final consistent = checkConsistency(normText, conversationHistory);
  if (consistent != null) {
    final dur = state.slots['duration'];
    final reply = dur != null
        ? (isProxy
            ? '(Mother) As I said doctor, $dur now.'
            : 'As I said doctor, $dur now.')
        : consistent;
    return ChatResult(
      reply: reply,
      intentId: 'consistency_check',
      type: 'consistency',
      normalisedText: normText,
      temperamentApplied: temperament,
      phase: state.phase.name,
    );
  }

  // ── Clusters (explicit broad history/exam requests) ─────────────────────
  final clusterIntentIds = resolveClusterIntents(normText, caseData);
  if (clusterIntentIds.length > 1) {
    final matchedIds = <String>[];
    final replies = <String>[];
    final scoredRows = <Map<String, dynamic>>[];
    String? clusterRule;
    for (final id in clusterIntentIds) {
      if (askedIntents.contains(id)) continue;
      final entry = intentMap[id] as Map<String, dynamic>?;
      if (entry == null) continue;
      final prior = state.intentAskCount[id] ?? 0;
      state.updateTrust(register: register, intentId: id);
      final resolved = patientReplyText(
        entry,
        normText,
        state: state,
        intentId: id,
        register: register,
        priorAskCount: prior,
      );
      matchedIds.add(id);
      scoredRows.add({'intentId': id, 'label': entry['label']});
      replies.add('[${entry['label']}] ${resolved.text}');
      clusterRule ??= resolved.ruleMatched;
      state.setTopic(id);
      state.markTest(id);
      state.markFinding(id);
    }
    final scoreRes = scoreMoves(
      intentIds: matchedIds,
      scoringMap: scoringMap,
      alreadyAsked: askedIntents,
    );
    return ChatResult(
      reply: replies.isEmpty
          ? plainUnsure(caseData)
          : replies.join('\n\n---\n\n'),
      intentId: matchedIds.isEmpty ? null : matchedIds.first,
      type: 'cluster',
      score: scoreRes.totalDelta,
      pearl: matchedIds.isEmpty
          ? null
          : getPearl(matchedIds.first, diagnosis?['primary'] as String?),
      normalisedText: normText,
      temperamentApplied: temperament,
      clusterIntents: scoredRows,
      matchedIntentIds: matchedIds,
      confidence: 0.9,
      matchSource: 'cluster',
      phase: detectPhase(normText).name,
      validationWarnings: schemaWarnings,
      ruleMatched: clusterRule,
    );
  }

  // ── Hidden facts ────────────────────────────────────────────────────────
  final hidden = resolveHiddenFact(normText, caseData, askedIntents);
  if (hidden != null) {
    final key = hidden['factKey'] as String?;
    if (hidden['unlocked'] == true && key != null) {
      state.markHiddenUnlocked(key);
    }
    return ChatResult(
      reply: hidden['response'] as String,
      intentId: 'hidden_fact_$key',
      type: hidden['unlocked'] == true
          ? 'hidden_fact_unlocked'
          : 'hidden_fact_locked',
      normalisedText: normText,
      temperamentApplied: temperament,
      hiddenFact: key,
      unlocked: hidden['unlocked'] as bool?,
      phase: state.phase.name,
    );
  }

  // ── Phase 1+2: Fused move decision ──────────────────────────────────────
  final decision = resolveMove(
    normText: normText,
    state: state,
    caseData: caseData,
  );
  state.setPhase(decision.phase);

  // Sequence penalty (synthesis too early)
  final seqPen = sequencePenalty(
    phase: decision.phase,
    askedIntents: askedIntents,
    scoringMap: scoringMap,
  );

  if (decision.hasMatch) {
    final matchedIds = <String>[];
    final replies = <String>[];
    String? primaryPearl;
    MatchSource? src;
    String? lastRuleMatched;

    for (final m in decision.matches) {
      final intentId = m.intentId;
      final entry = intentMap[intentId] as Map<String, dynamic>?;
      src = m.primarySource;
      if (entry == null) {
        if (decision.matches.length == 1) {
          return ChatResult(
            reply: generateNotApplicable(intentId, caseData),
            intentId: intentId,
            type: 'not_applicable',
            normalisedText: normText,
            temperamentApplied: temperament,
            confidence: decision.confidence,
            matchSource: m.primarySource.name,
            phase: decision.phase.name,
          );
        }
        continue;
      }
      matchedIds.add(intentId);
      final prior = state.intentAskCount[intentId] ?? 0;
      state.updateTrust(register: register, intentId: intentId);
      final resolved = patientReplyText(
        entry,
        normText,
        state: state,
        intentId: intentId,
        register: register,
        priorAskCount: prior,
      );
      lastRuleMatched = resolved.ruleMatched;
      var text = enrichVoice(
        resolved.text,
        temperament,
        distressIntents.contains(intentId),
        rng,
        isProxy: isProxy,
      );
      replies.add(text);
      state.setTopic(intentId);
      state.markTest(intentId);
      state.markFinding(intentId);
      for (final e in extractSlots(text).entries) {
        state.putSlot(e.key, e.value);
      }
      primaryPearl ??= getPearl(intentId, diagnosis?['primary'] as String?);
    }

    if (replies.isEmpty) {
      MissLog.instance.record(
        caseId: caseId,
        message: message,
        normalised: normText,
        reason: 'not_in_case',
        confidence: decision.confidence,
      );
      return ChatResult(
        reply: generateNegativeReply(normText, caseData),
        type: 'negative',
        normalisedText: normText,
        temperamentApplied: temperament,
        phase: decision.phase.name,
      );
    }

    final scoreRes = scoreMoves(
      intentIds: matchedIds,
      scoringMap: scoringMap,
      alreadyAsked: askedIntents,
    );
    var pts = scoreRes.totalDelta;
    if (seqPen > 0) pts = (pts - seqPen).clamp(0, 9999);

    // Mid confidence: still answer if in case, but patient may be brief
    final type = decision.matches.length > 1
        ? 'multi_match'
        : (decision.reason == 'topic_followup'
            ? 'followup'
            : (decision.confidence < 0.5 ? 'weak_match' : 'match'));

    return ChatResult(
      reply: replies.join(' '),
      intentId: matchedIds.first,
      type: type,
      score: pts,
      penalty: seqPen > 0 ? seqPen : null,
      pearl: primaryPearl,
      normalisedText: normText,
      temperamentApplied: temperament,
      matchedIntentIds: matchedIds,
      confidence: decision.confidence,
      matchSource: src?.name ?? decision.reason,
      phase: decision.phase.name,
      validationWarnings: schemaWarnings,
      ruleMatched: lastRuleMatched,
    );
  }

  // ── Unmatched ladder (no tutor) ─────────────────────────────────────────
  MissLog.instance.record(
    caseId: caseId,
    message: message,
    normalised: normText,
    reason: decision.reason ?? 'unmatched',
    confidence: decision.confidence,
  );

  final caseSymptoms = (caseData['case_symptoms'] as List?)?.cast<String>() ??
      (caseData['symptoms'] as List?)?.cast<String>() ??
      [];
  final hasSymptom =
      caseSymptoms.any((s) => normText.contains(s.toLowerCase()));

  if (hasSymptom || decision.confidence > 0.15) {
    return ChatResult(
      reply: enrichVoice(
        plainUnsure(caseData),
        temperament,
        false,
        rng,
        isProxy: isProxy,
      ),
      type: 'near_miss',
      normalisedText: normText,
      temperamentApplied: temperament,
      confidence: decision.confidence,
      phase: decision.phase.name,
      matchSource: decision.reason,
    );
  }

  return ChatResult(
    reply: enrichVoice(
      generateNegativeReply(normText, caseData),
      temperament,
      false,
      rng,
      isProxy: isProxy,
    ),
    type: 'negative',
    normalisedText: normText,
    temperamentApplied: temperament,
    confidence: decision.confidence,
    phase: decision.phase.name,
  );
}

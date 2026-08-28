class PatientInfo {
  final String name;
  final dynamic age;
  final String sex;
  final String? occupation;
  final String? avatar;

  const PatientInfo({
    required this.name,
    required this.age,
    required this.sex,
    this.occupation,
    this.avatar,
  });

  factory PatientInfo.fromJson(Map<String, dynamic> j) => PatientInfo(
        name: j['name'] as String? ?? 'Unknown',
        age: j['age'],
        sex: j['sex'] as String? ?? '',
        occupation: j['occupation'] as String?,
        avatar: j['avatar'] as String?,
      );

  String get ageLabel {
    if (age is num) {
      final a = (age as num).toInt();
      if (a == 0) return 'Neonate';
      if (a < 12) return '$a mo';
      return '$a y';
    }
    return age?.toString() ?? '?';
  }
}

class CaseModel {
  final String caseId;
  final String discipline;
  final String difficulty;
  final String presentingComplaint;
  final PatientInfo patient;
  final Map<String, dynamic> diagnosis;
  final Map<String, dynamic> intentMap;
  final Map<String, dynamic> scoringMap;
  final Map<String, dynamic>? hiddenFacts;
  final List differentials;
  final int? timeLimit;
  final List trapActions;
  final String? hospital;
  final Map<String, dynamic> raw;

  const CaseModel({
    required this.caseId,
    required this.discipline,
    required this.difficulty,
    required this.presentingComplaint,
    required this.patient,
    required this.diagnosis,
    required this.intentMap,
    required this.scoringMap,
    this.hiddenFacts,
    this.differentials = const [],
    this.timeLimit,
    this.trapActions = const [],
    this.hospital,
    required this.raw,
  });

  factory CaseModel.fromJson(Map<String, dynamic> j) {
    return CaseModel(
      caseId: j['caseId'] as String? ?? j['id'] as String? ?? 'unknown',
      discipline: j['discipline'] as String? ?? 'peds',
      difficulty: j['difficulty'] as String? ?? 'medium',
      presentingComplaint:
          j['presentingComplaint'] as String? ?? j['presenting_complaint'] as String? ?? '',
      patient: PatientInfo.fromJson(
        (j['patient'] as Map<String, dynamic>?) ?? {},
      ),
      diagnosis: (j['diagnosis'] as Map<String, dynamic>?) ?? {},
      intentMap: (j['intentMap'] as Map<String, dynamic>?) ?? {},
      scoringMap: (j['scoringMap'] as Map<String, dynamic>?) ?? {},
      hiddenFacts: j['hidden_facts'] as Map<String, dynamic>?,
      differentials: (j['differentials'] as List?) ?? [],
      timeLimit: (j['timeLimit'] as num?)?.toInt(),
      trapActions: (j['trapActions'] as List?) ?? [],
      hospital: j['hospital'] as String?,
      raw: j,
    );
  }

  String get primaryDiagnosis =>
      diagnosis['primary'] as String? ?? 'Undisclosed';

  List<String> get mustAsk =>
      (scoringMap['mustAsk'] as List?)?.cast<String>() ?? [];

  List<String> get shouldAsk =>
      (scoringMap['shouldAsk'] as List?)?.cast<String>() ?? [];

  int get maxScore {
    final must = mustAsk.length * ((scoringMap['pointsMust'] as num?)?.toInt() ?? 15);
    final should = shouldAsk.length * ((scoringMap['pointsBase'] as num?)?.toInt() ?? 10);
    return must + should;
  }
}

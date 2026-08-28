import 'ontology.dart';

/// Phase 3 — Expanded session dialogue state.

class DialogueState {
  String? activeTopic;
  final List<String> topicStack = [];
  final Map<String, String> slots = {};
  final Map<String, int> intentAskCount = {};
  final Set<String> findingsRevealed = {};
  final Set<String> testsOrdered = {};
  final Set<String> unlockedHidden = {};
  ClinicalPhase phase = ClinicalPhase.history;

  String? pendingClarificationIntent;
  String? pendingClarificationLabel;

  final List<String> recentNorm = [];

  void noteStudent(String normText) {
    recentNorm.add(normText);
    if (recentNorm.length > 30) recentNorm.removeAt(0);
  }

  void setTopic(String intentId) {
    if (activeTopic != null && activeTopic != intentId) {
      topicStack.add(activeTopic!);
      if (topicStack.length > 8) topicStack.removeAt(0);
    }
    activeTopic = intentId;
    intentAskCount[intentId] = (intentAskCount[intentId] ?? 0) + 1;
    clearClarification();
  }

  int askCount(String intentId) => intentAskCount[intentId] ?? 0;

  void setPhase(ClinicalPhase p) => phase = p;

  void setClarification(String intentId, String label) {
    pendingClarificationIntent = intentId;
    pendingClarificationLabel = label;
  }

  void clearClarification() {
    pendingClarificationIntent = null;
    pendingClarificationLabel = null;
  }

  bool get hasPendingClarification => pendingClarificationIntent != null;

  void putSlot(String key, String value) {
    if (value.trim().isEmpty) return;
    slots[key] = value.trim();
  }

  void markTest(String intentId) {
    if (intentId.startsWith('ix_')) testsOrdered.add(intentId);
  }

  void markFinding(String intentId) {
    if (intentId.startsWith('exam_')) findingsRevealed.add(intentId);
  }

  void markHiddenUnlocked(String key) => unlockedHidden.add(key);

  void reset() {
    activeTopic = null;
    topicStack.clear();
    slots.clear();
    intentAskCount.clear();
    findingsRevealed.clear();
    testsOrdered.clear();
    unlockedHidden.clear();
    phase = ClinicalPhase.history;
    clearClarification();
    recentNorm.clear();
  }

  Map<String, dynamic> toJson() => {
        'activeTopic': activeTopic,
        'topicStack': List<String>.from(topicStack),
        'slots': Map<String, String>.from(slots),
        'intentAskCount': Map<String, int>.from(intentAskCount),
        'findingsRevealed': findingsRevealed.toList(),
        'testsOrdered': testsOrdered.toList(),
        'unlockedHidden': unlockedHidden.toList(),
        'phase': phase.name,
      };
}

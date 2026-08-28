import 'package:flutter/foundation.dart';

import '../core/dialogue_state.dart';
import '../core/engine.dart';
import '../core/miss_log.dart';
import '../models/case_model.dart';
import '../models/chat_message.dart';
import 'app_config.dart';
import 'connectivity_helper.dart';
import 'supabase_api.dart';
import 'worker_api.dart';

class SessionController extends ChangeNotifier {
  CaseModel? caseData;
  final List<ChatMessage> messages = [];
  final List<String> askedIntents = [];
  final DialogueState dialogue = DialogueState();
  int totalScore = 0;
  int penalties = 0;
  bool sessionEnded = false;
  bool isSending = false;
  DateTime? startedAt;

  EngineSource lastEngineSource = EngineSource.offline;
  String? lastError;

  final WorkerApi _worker = WorkerApi();
  final SupabaseApi _supabase = SupabaseApi();

  void start(CaseModel c) {
    caseData = c;
    messages.clear();
    askedIntents.clear();
    dialogue.reset();
    totalScore = 0;
    penalties = 0;
    sessionEnded = false;
    isSending = false;
    lastError = null;
    startedAt = DateTime.now();
    lastEngineSource = EngineSource.offline;

    final intro =
        '${c.patient.avatar ?? '👤'} ${c.patient.name} · ${c.patient.ageLabel} · ${c.patient.sex}\n\n'
        'Presenting: ${c.presentingComplaint}';
    messages.add(ChatMessage(role: 'system', content: intro));
    notifyListeners();
  }

  Future<void> sendMessage(String text) async {
    if (caseData == null || sessionEnded || text.trim().isEmpty || isSending) {
      return;
    }

    isSending = true;
    lastError = null;
    messages.add(ChatMessage(role: 'student', content: text.trim()));
    notifyListeners();

    final history = messages
        .where((m) => m.role == 'patient' || m.role == 'student')
        .map((m) => m.toHistoryMap())
        .toList();

    ChatResult result;
    try {
      final source = await ConnectivityHelper.instance.resolveSource();
      lastEngineSource = source;

      if (source == EngineSource.worker) {
        result = await _chatViaWorker(text, history);
        // Keep local dialogue state roughly in sync for offline continuity
        if (result.intentId != null &&
            result.type != 'penalty' &&
            result.type != 'clarification') {
          dialogue.setTopic(result.intentId!);
        }
      } else {
        result = processChat(
          caseData: caseData!.raw,
          message: text,
          conversationHistory: history,
          askedIntents: List.from(askedIntents),
          dialogue: dialogue,
        );
      }
    } catch (e) {
      lastEngineSource = EngineSource.offline;
      lastError = e.toString();
      result = processChat(
        caseData: caseData!.raw,
        message: text,
        conversationHistory: history,
        askedIntents: List.from(askedIntents),
        dialogue: dialogue,
      );
    }

    _applyResult(result);
    isSending = false;
    notifyListeners();
  }

  Future<ChatResult> _chatViaWorker(String text, List history) async {
    final data = await _worker.chat(
      caseId: caseData!.caseId,
      message: text,
      conversationHistory: history,
      askedIntents: List.from(askedIntents),
    );

    final type = data['type']?.toString() ?? 'match';
    if ((type == 'fallback' || type == 'negative') &&
        (data['reply'] == null || (data['reply'] as String).length < 8)) {
      try {
        final enriched = await _worker.getAnswer(
          caseId: caseData!.caseId,
          question: text,
        );
        if (enriched['found'] == true && enriched['answer'] != null) {
          data['reply'] = enriched['answer'];
          data['type'] = 'supabase_answer';
        }
      } catch (_) {}
    }

    return ChatResult(
      reply: data['reply']?.toString() ?? '…',
      intentId: data['intentId'] as String?,
      type: data['type']?.toString() ?? 'match',
      isDangerous: data['isDangerous'] == true,
      score: (data['score'] as num?)?.toInt() ?? 0,
      penalty: (data['penalty'] as num?)?.toInt(),
      pearl: data['pearl'] as String?,
      normalisedText: data['normalisedText']?.toString() ?? text,
      temperamentApplied: data['temperamentApplied'] as String?,
      clusterIntents: (data['clusterIntents'] as List?)
          ?.map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
      hiddenFact: data['hiddenFact'] as String?,
      unlocked: data['unlocked'] as bool?,
      matchedIntentIds: (data['matchedIntentIds'] as List?)?.cast<String>(),
    );
  }

  void _applyResult(ChatResult result) {
    if (result.intentId != null &&
        result.type != 'penalty' &&
        result.type != 'consistency' &&
        result.type != 'not_applicable' &&
        result.type != 'clarification' &&
        result.type != 'clarification_rejected' &&
        result.type != 'followup' &&
        result.type != 'elaborate' &&
        !askedIntents.contains(result.intentId)) {
      askedIntents.add(result.intentId!);
    }

    if (result.matchedIntentIds != null) {
      for (final id in result.matchedIntentIds!) {
        if (!askedIntents.contains(id)) askedIntents.add(id);
      }
    }

    if (result.clusterIntents != null) {
      for (final ci in result.clusterIntents!) {
        final id = ci['intentId'] as String?;
        if (id != null && !askedIntents.contains(id)) askedIntents.add(id);
      }
    }

    totalScore += result.score;
    if (result.isDangerous && result.penalty != null) {
      penalties += result.penalty!;
      totalScore = (totalScore - result.penalty!).clamp(0, 9999);
    }

    messages.add(ChatMessage(
      role: 'patient',
      content: result.reply,
      intentId: result.intentId,
      type: result.type,
      score: result.score,
      pearl: result.pearl,
      isDangerous: result.isDangerous,
    ));
  }

  void endSession() {
    sessionEnded = true;
    notifyListeners();
  }

  Future<Map<String, dynamic>> submitScore() async {
    if (caseData == null) return {'ok': false};
    final elapsed = startedAt == null
        ? 0
        : DateTime.now().difference(startedAt!).inSeconds;

    final results = <String, dynamic>{};

    try {
      final w = await _worker.submitScore(
        caseId: caseData!.caseId,
        score: totalScore,
        penalties: penalties,
        discipline: caseData!.discipline,
        timeTaken: elapsed,
        studentName: AppConfig.instance.studentName,
      );
      results['worker'] = w;
    } catch (e) {
      results['worker_error'] = e.toString();
    }

    try {
      final ok = await _supabase.insertScore(
        caseId: caseData!.caseId,
        score: totalScore,
        penalties: penalties,
        discipline: caseData!.discipline,
        timeTaken: elapsed,
        studentName: AppConfig.instance.studentName,
      );
      results['supabase'] = ok;
    } catch (e) {
      results['supabase_error'] = e.toString();
    }

    // Flush miss log learning payload when online
    try {
      final misses = MissLog.instance.exportPayload();
      if ((misses['count'] as int? ?? 0) > 0) {
        results['miss_log_count'] = misses['count'];
        // Best-effort: post as score metadata is not ideal; store locally
        // and expose via settings export. Worker may add /admin/miss-log later.
      }
    } catch (_) {}

    return results;
  }

  int get mustAsked {
    if (caseData == null) return 0;
    return caseData!.mustAsk.where(askedIntents.contains).length;
  }

  int get shouldAsked {
    if (caseData == null) return 0;
    return caseData!.shouldAsk.where(askedIntents.contains).length;
  }

  double get progressPercent {
    if (caseData == null) return 0;
    final total = caseData!.mustAsk.length + caseData!.shouldAsk.length;
    if (total == 0) return 0;
    return ((mustAsked + shouldAsked) / total).clamp(0.0, 1.0);
  }
}

import '../core/engine.dart';
import '../core/dialogue_state.dart';
import 'app_config.dart';
import 'connectivity_helper.dart';
import 'supabase_api.dart';
import 'worker_api.dart';

/// Unified turn pipeline across Flutter offline engine, CLER Worker, and Plan/Supabase.
///
/// Flow (hybrid, default):
///   1. Always run local [processChat] (gradeable, offline-safe).
///   2. If online and local is a miss → GET Worker /get-answer (Plan reply_bank).
///   3. If still a miss → POST Worker /ask-question (Plan pending_questions queue).
///   4. Optional: prefer Worker /chat when [AppConfig.preferOnlineEngine].
///
/// Backend URLs and anon key are baked into AppConfig (not user-editable).
class IntegrationHub {
  IntegrationHub({
    WorkerApi? worker,
    SupabaseApi? supabase,
  })  : _worker = worker ?? WorkerApi(),
        _supabase = supabase ?? SupabaseApi();

  final WorkerApi _worker;
  final SupabaseApi _supabase;

  static const _missTypes = {
    'negative',
    'near_miss',
    'fallback',
    'not_applicable',
  };

  bool _isMiss(ChatResult r) =>
      _missTypes.contains(r.type) ||
      (r.intentId == null && r.score == 0 && !r.isDangerous);

  /// Full turn: local engine + Plan cache/queue + optional remote chat.
  Future<HubTurnResult> handleTurn({
    required Map<String, dynamic> caseData,
    required String caseId,
    required String message,
    required List conversationHistory,
    required List<String> askedIntents,
    required DialogueState dialogue,
  }) async {
    final cfg = AppConfig.instance;
    final online = !cfg.forceOffline &&
        cfg.hasWorker &&
        await ConnectivityHelper.isOnline();

    // ── 1. Local engine (always) ──────────────────────────────────────────
    final local = processChat(
      caseData: caseData,
      message: message,
      conversationHistory: conversationHistory,
      askedIntents: askedIntents,
      dialogue: dialogue,
    );

    // Prefer remote chat when configured and online
    if (online && cfg.preferOnlineEngine) {
      try {
        final remote = await _worker.chat(
          caseId: caseId,
          message: message,
          conversationHistory: conversationHistory,
          askedIntents: askedIntents,
        );
        final remoteResult = _chatMapToResult(remote, message);
        if (!_isMiss(remoteResult)) {
          return HubTurnResult(
            result: remoteResult,
            source: HubSource.workerChat,
            queued: false,
          );
        }
        // Remote miss → still try reply_bank / queue below using local as base
      } catch (_) {
        // fall through to local + Plan path
      }
    }

    if (!_isMiss(local)) {
      return HubTurnResult(
        result: local,
        source: HubSource.localEngine,
        queued: false,
      );
    }

    // ── 2–3. Online miss: Plan reply_bank then queue ─────────────────────
    if (!online) {
      return HubTurnResult(
        result: local,
        source: HubSource.localEngineOfflineMiss,
        queued: false,
      );
    }

    // get-answer via Worker (preferred) then direct Supabase function
    Map<String, dynamic>? bank;
    try {
      bank = await _worker.getAnswer(caseId: caseId, question: message);
    } catch (_) {
      if (cfg.hasSupabase) {
        try {
          bank = await _supabase.getAnswer(caseId: caseId, question: message);
        } catch (_) {}
      }
    }

    final found = bank != null &&
        (bank['found'] == true ||
            bank['answer'] != null ||
            bank['reply'] != null);
    final answer = bank?['answer'] ?? bank?['reply'];

    if (found && answer != null && '$answer'.trim().isNotEmpty) {
      return HubTurnResult(
        result: ChatResult(
          reply: '$answer'.trim(),
          intentId: bank?['intentId'] as String?,
          type: 'reply_bank',
          score: 0, // bank answers are learning layer; scoring stays rule-engine
          normalisedText: local.normalisedText,
          confidence: (bank?['confidence'] as num?)?.toDouble(),
          matchSource: 'plan_reply_bank',
        ),
        source: HubSource.planReplyBank,
        queued: false,
      );
    }

    // Queue unknown question for overnight batch (Plan)
    var queued = false;
    try {
      await _worker.askQuestion(
        caseId: caseId,
        question: message,
        caseContext: {
          'presentingComplaint': caseData['presentingComplaint'],
          'diagnosis': caseData['diagnosis'],
        },
      );
      queued = true;
    } catch (_) {
      if (cfg.hasSupabase) {
        try {
          await _supabase.askQuestion(
            caseId: caseId,
            question: message,
            caseContext: {
              'presentingComplaint': caseData['presentingComplaint'],
              'diagnosis': caseData['diagnosis'],
            },
          );
          queued = true;
        } catch (_) {}
      }
    }

    return HubTurnResult(
      result: local, // patient already deflected offline-style
      source: HubSource.queuedMiss,
      queued: queued,
    );
  }

  Future<Map<String, dynamic>> submitScoreEnd({
    required String caseId,
    required int score,
    required int penalties,
    required String discipline,
    required int timeTaken,
    String? studentName,
  }) async {
    final out = <String, dynamic>{};
    final cfg = AppConfig.instance;
    if (cfg.hasWorker) {
      try {
        out['worker'] = await _worker.submitScore(
          caseId: caseId,
          score: score,
          penalties: penalties,
          discipline: discipline,
          timeTaken: timeTaken,
          studentName: studentName,
        );
      } catch (e) {
        out['worker_error'] = e.toString();
      }
    }
    if (cfg.hasSupabase) {
      try {
        out['supabase'] = await _supabase.insertScore(
          caseId: caseId,
          score: score,
          penalties: penalties,
          discipline: discipline,
          timeTaken: timeTaken,
          studentName: studentName,
        );
      } catch (e) {
        out['supabase_error'] = e.toString();
      }
    }
    return out;
  }

  ChatResult _chatMapToResult(Map<String, dynamic> data, String fallbackNorm) {
    return ChatResult(
      reply: data['reply']?.toString() ?? '…',
      intentId: data['intentId'] as String?,
      type: data['type']?.toString() ?? 'match',
      isDangerous: data['isDangerous'] == true,
      score: (data['score'] as num?)?.toInt() ?? 0,
      penalty: (data['penalty'] as num?)?.toInt(),
      pearl: data['pearl'] as String?,
      normalisedText: data['normalisedText']?.toString() ?? fallbackNorm,
      temperamentApplied: data['temperamentApplied'] as String?,
      clusterIntents: (data['clusterIntents'] as List?)
          ?.map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
      hiddenFact: data['hiddenFact'] as String?,
      unlocked: data['unlocked'] as bool?,
      matchedIntentIds: (data['matchedIntentIds'] as List?)?.cast<String>(),
      confidence: (data['confidence'] as num?)?.toDouble(),
      matchSource: data['matchSource']?.toString() ?? 'worker',
      ruleMatched: data['ruleMatched'] as String?,
    );
  }
}

enum HubSource {
  localEngine,
  localEngineOfflineMiss,
  workerChat,
  planReplyBank,
  queuedMiss,
}

class HubTurnResult {
  final ChatResult result;
  final HubSource source;
  final bool queued;

  HubTurnResult({
    required this.result,
    required this.source,
    required this.queued,
  });
}

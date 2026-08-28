import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/case_model.dart';
import 'app_config.dart';

class WorkerApiException implements Exception {
  final String message;
  final int? status;
  WorkerApiException(this.message, [this.status]);
  @override
  String toString() => 'WorkerApiException($status): $message';
}

/// Client for the Cloudflare Worker (ClerkAI / bigclerk).
class WorkerApi {
  WorkerApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  AppConfig get _cfg => AppConfig.instance;

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = _cfg.workerRoot;
    return Uri.parse('$base$path').replace(queryParameters: query);
  }

  Future<Map<String, dynamic>> health() async {
    final res = await _client
        .get(_uri('/health'))
        .timeout(const Duration(seconds: 8));
    return _decode(res);
  }

  Future<List<CaseModel>> fetchCases({String discipline = 'peds'}) async {
    final res = await _client
        .get(_uri('/cases', {'discipline': discipline}))
        .timeout(const Duration(seconds: 12));
    final data = _decode(res);
    final list = (data['cases'] as List?) ?? [];
    return list
        .map((e) => CaseModel.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// POST /chat — remote patient simulation.
  Future<Map<String, dynamic>> chat({
    required String caseId,
    required String message,
    List conversationHistory = const [],
    List<String> askedIntents = const [],
    String personality = 'neutral',
  }) async {
    final res = await _client
        .post(
          _uri('/chat'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'caseId': caseId,
            'message': message,
            'conversationHistory': conversationHistory,
            'askedIntents': askedIntents,
            'personality': personality,
          }),
        )
        .timeout(const Duration(seconds: 20));
    return _decode(res);
  }

  /// POST /scores
  Future<Map<String, dynamic>> submitScore({
    required String caseId,
    required int score,
    String? studentName,
    int penalties = 0,
    bool correct = false,
    String discipline = 'peds',
    int timeTaken = 0,
  }) async {
    final res = await _client
        .post(
          _uri('/scores'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'caseId': caseId,
            'studentName': studentName ?? _cfg.studentName,
            'score': score,
            'penalties': penalties,
            'correct': correct,
            'discipline': discipline,
            'timeTaken': timeTaken,
          }),
        )
        .timeout(const Duration(seconds: 10));
    return _decode(res);
  }

  /// GET /leaderboard?discipline=
  Future<List<Map<String, dynamic>>> leaderboard({String? discipline}) async {
    final q = <String, String>{};
    if (discipline != null && discipline.isNotEmpty) {
      q['discipline'] = discipline;
    }
    final res = await _client
        .get(_uri('/leaderboard', q.isEmpty ? null : q))
        .timeout(const Duration(seconds: 10));
    final data = _decode(res);
    final list = (data['leaderboard'] as List?) ?? [];
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// GET /get-answer — Worker → KV → Supabase reply bank
  Future<Map<String, dynamic>> getAnswer({
    required String caseId,
    required String question,
  }) async {
    final res = await _client
        .get(_uri('/get-answer', {
          'caseId': caseId,
          'question': question,
        }))
        .timeout(const Duration(seconds: 15));
    return _decode(res);
  }

  /// POST /ask-question — queues / fetches via Worker + Supabase
  Future<Map<String, dynamic>> askQuestion({
    required String caseId,
    required String question,
    Map<String, dynamic> caseContext = const {},
    String personality = 'neutral',
  }) async {
    final res = await _client
        .post(
          _uri('/ask-question'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'caseId': caseId,
            'question': question,
            'caseContext': caseContext,
            'personality': personality,
          }),
        )
        .timeout(const Duration(seconds: 20));
    return _decode(res);
  }

  Map<String, dynamic> _decode(http.Response res) {
    Map<String, dynamic> body;
    try {
      final decoded = jsonDecode(res.body);
      body = decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{'data': decoded};
    } catch (_) {
      throw WorkerApiException('Invalid JSON from worker', res.statusCode);
    }
    if (res.statusCode >= 400) {
      throw WorkerApiException(
        body['error']?.toString() ?? res.body,
        res.statusCode,
      );
    }
    return body;
  }
}

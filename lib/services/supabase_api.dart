import 'dart:convert';

import 'package:http/http.dart' as http;

import 'app_config.dart';

/// Direct calls to Supabase Edge Functions (same ones the Worker uses).
/// Prefer going through [WorkerApi] when possible so KV cache stays warm.
class SupabaseApi {
  SupabaseApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  AppConfig get _cfg => AppConfig.instance;

  Map<String, String> get _headers => {
        'Authorization': 'Bearer ${_cfg.supabaseAnonKey}',
        'apikey': _cfg.supabaseAnonKey,
        'Content-Type': 'application/json',
      };

  Uri _fn(String name, [Map<String, String>? query]) {
    final base = _cfg.supabaseUrl.trim().replaceAll(RegExp(r'/$'), '');
    return Uri.parse('$base/functions/v1/$name').replace(queryParameters: query);
  }

  /// GET functions/v1/get-answer
  Future<Map<String, dynamic>> getAnswer({
    required String caseId,
    required String question,
  }) async {
    final res = await _client
        .get(
          _fn('get-answer', {
            'caseId': caseId,
            'question': question,
          }),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 15));
    return _decode(res);
  }

  /// POST functions/v1/ask-question
  Future<Map<String, dynamic>> askQuestion({
    required String caseId,
    required String question,
    Map<String, dynamic> caseContext = const {},
    String personality = 'neutral',
  }) async {
    final res = await _client
        .post(
          _fn('ask-question'),
          headers: _headers,
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

  /// Optional: write a score row if you have a `scores` table with RLS for anon.
  /// Safe no-op on failure so the app still works without that table.
  Future<bool> insertScore({
    required String caseId,
    required int score,
    String? studentName,
    int penalties = 0,
    String discipline = 'peds',
    int timeTaken = 0,
  }) async {
    final base = _cfg.supabaseUrl.trim().replaceAll(RegExp(r'/$'), '');
    final uri = Uri.parse('$base/rest/v1/scores');
    try {
      final res = await _client
          .post(
            uri,
            headers: {
              ..._headers,
              'Prefer': 'return=minimal',
            },
            body: jsonEncode({
              'case_id': caseId,
              'student_name': studentName ?? _cfg.studentName,
              'score': score,
              'penalties': penalties,
              'discipline': discipline,
              'time_taken': timeTaken,
            }),
          )
          .timeout(const Duration(seconds: 10));
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> ping() async {
    // Lightweight probe via get-answer
    return getAnswer(caseId: 'test', question: 'test');
  }

  Map<String, dynamic> _decode(http.Response res) {
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return {'data': decoded};
    } catch (_) {
      return {
        'error': res.body,
        'status': res.statusCode,
      };
    }
  }
}

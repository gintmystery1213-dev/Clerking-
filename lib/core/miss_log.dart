import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Local log of unmatched / low-confidence questions for later pattern mining.
/// Optionally flushed to Worker/Supabase when online.
class MissLog {
  MissLog._();
  static final MissLog instance = MissLog._();

  static const _storageKey = 'cler_miss_log_v1';
  final List<Map<String, dynamic>> _buffer = [];

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_storageKey);
    if (raw == null) return;
    try {
      final list = jsonDecode(raw) as List;
      _buffer
        ..clear()
        ..addAll(list.map((e) => Map<String, dynamic>.from(e as Map)));
    } catch (_) {}
  }

  void record({
    required String caseId,
    required String message,
    required String normalised,
    String? reason,
    double? confidence,
  }) {
    _buffer.add({
      'ts': DateTime.now().toIso8601String(),
      'caseId': caseId,
      'message': message,
      'normalised': normalised,
      'reason': reason ?? 'unmatched',
      'confidence': confidence,
    });
    if (_buffer.length > 200) {
      _buffer.removeRange(0, _buffer.length - 200);
    }
    // Fire-and-forget persist
    _persist();
  }

  Future<void> _persist() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_storageKey, jsonEncode(_buffer));
  }

  List<Map<String, dynamic>> snapshot() =>
      List<Map<String, dynamic>>.from(_buffer);

  Future<void> clear() async {
    _buffer.clear();
    await _persist();
  }

  /// Payload suitable for Worker/Supabase batch ingest.
  Map<String, dynamic> exportPayload() => {
        'type': 'miss_log',
        'count': _buffer.length,
        'entries': snapshot(),
      };
}

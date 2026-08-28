import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/case_model.dart';
import 'app_config.dart';
import 'connectivity_helper.dart';
import 'worker_api.dart';

class CaseRepository {
  CaseRepository._();
  static final CaseRepository instance = CaseRepository._();

  final WorkerApi _worker = WorkerApi();
  List<CaseModel>? _cache;
  String? _cacheSource; // 'worker' | 'assets'

  String? get lastSource => _cacheSource;

  Future<List<CaseModel>> loadCases({
    String discipline = 'peds',
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _cache != null) {
      return _filter(_cache!, discipline);
    }

    final source = await ConnectivityHelper.instance.resolveSource();
    if (source == EngineSource.worker) {
      try {
        final remote = await _worker.fetchCases(discipline: discipline);
        if (remote.isNotEmpty) {
          _cache = remote;
          _cacheSource = 'worker';
          return remote;
        }
      } catch (_) {
        // fall through to assets
      }
    }

    final local = await _loadFromAssets();
    _cache = local;
    _cacheSource = 'assets';
    return _filter(local, discipline);
  }

  Future<List<CaseModel>> _loadFromAssets() async {
    final raw = await rootBundle.loadString(
      'assets/knowledge/cases/peds_cases.json',
    );
    final decoded = jsonDecode(raw);
    final list = (decoded is Map && decoded['cases'] is List)
        ? decoded['cases'] as List
        : (decoded is List ? decoded : <dynamic>[]);

    return list
        .map((e) => CaseModel.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  List<CaseModel> _filter(List<CaseModel> all, String discipline) {
    if (discipline == 'all') return List.from(all);
    return all.where((c) => c.discipline == discipline).toList();
  }

  Future<CaseModel?> getById(String caseId) async {
    final all = await loadCases(discipline: 'all');
    try {
      return all.firstWhere((c) => c.caseId == caseId);
    } catch (_) {
      return null;
    }
  }

  void clearCache() {
    _cache = null;
    _cacheSource = null;
  }

  Future<String> probeSources() async {
    final mode = AppConfig.instance.mode;
    final workerOk = await ConnectivityHelper.instance.workerReachable();
    final sbOk = await ConnectivityHelper.instance.supabaseReachable();
    return 'mode=$mode · worker=${workerOk ? "up" : "down"} · supabase=${sbOk ? "up" : "down"}';
  }
}

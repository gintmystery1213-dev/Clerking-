import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;

import 'app_config.dart';
import 'worker_api.dart';

enum EngineSource { offline, worker }

class ConnectivityHelper {
  ConnectivityHelper._();
  static final ConnectivityHelper instance = ConnectivityHelper._();

  final WorkerApi _worker = WorkerApi();

  /// Resolve whether to use remote Worker based on mode + reachability.
  Future<EngineSource> resolveSource() async {
    final mode = AppConfig.instance.mode;
    if (mode == 'offline') return EngineSource.offline;
    if (mode == 'online') return EngineSource.worker;

    // auto
    final net = await Connectivity().checkConnectivity();
    final offlineNet = net.every((r) => r == ConnectivityResult.none);
    if (offlineNet) return EngineSource.offline;

    try {
      await _worker.health();
      return EngineSource.worker;
    } catch (_) {
      return EngineSource.offline;
    }
  }

  Future<bool> workerReachable() async {
    try {
      await _worker.health();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> supabaseReachable() async {
    try {
      final cfg = AppConfig.instance;
      final uri = Uri.parse(
        '${cfg.supabaseUrl.replaceAll(RegExp(r'/$'), '')}/auth/v1/health',
      );
      final res = await http
          .get(uri, headers: {'apikey': cfg.supabaseAnonKey})
          .timeout(const Duration(seconds: 6));
      return res.statusCode >= 200 && res.statusCode < 500;
    } catch (_) {
      return false;
    }
  }
}

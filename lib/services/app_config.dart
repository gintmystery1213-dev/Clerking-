import 'package:shared_preferences/shared_preferences.dart';

/// Runtime config for CLER.
///
/// Backend endpoints and the Supabase anon key are **baked in** — never
/// shown or editable in the UI. Only user preferences (mode, display name)
/// are persisted locally.
class AppConfig {
  AppConfig._();
  static final AppConfig instance = AppConfig._();

  // ── Hard-wired backends (not user-facing) ──────────────────────────────
  static const String _workerBaseUrl = 'https://bigclerk.grentwalter300.workers.dev';
  static const String _supabaseUrl =
      'https://wxmgtugqiisnojqbezby.supabase.co';
  static const String _supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Ind4bWd0dWdxaWlzbm9qcWJlemJ5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzgwMTE4NTgsImV4cCI6MjA5MzU4Nzg1OH0.wo1sYZnxBrsjuWvP11luDWkKXesrghMQifM_qVMfZIU';

  /// auto | online | offline
  String mode = 'auto';
  String studentName = 'Anonymous';

  /// When true and online, prefer Worker /chat over local engine for matches.
  /// Kept internal (not exposed in Settings) — local-first is the default.
  bool preferOnlineEngine = false;

  String get workerBaseUrl => _workerBaseUrl;
  String get supabaseUrl => _supabaseUrl;
  String get supabaseAnonKey => _supabaseAnonKey;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    mode = p.getString('mode') ?? 'auto';
    studentName = p.getString('studentName') ?? 'Anonymous';
    preferOnlineEngine = p.getBool('preferOnlineEngine') ?? false;
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('mode', mode);
    await p.setString('studentName', studentName.trim());
    await p.setBool('preferOnlineEngine', preferOnlineEngine);
  }

  String get workerRoot {
    var u = workerBaseUrl.trim();
    if (u.endsWith('/')) u = u.substring(0, u.length - 1);
    return u;
  }

  bool get hasWorker => workerBaseUrl.trim().isNotEmpty;
  bool get hasSupabase =>
      supabaseUrl.trim().isNotEmpty && supabaseAnonKey.trim().isNotEmpty;

  /// Force offline local-only turns.
  bool get forceOffline => mode == 'offline';
}

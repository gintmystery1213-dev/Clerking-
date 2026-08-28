import 'package:shared_preferences/shared_preferences.dart';

/// Runtime config for Worker + Supabase.
/// Defaults match the original wrangler.jsonc values.
class AppConfig {
  AppConfig._();
  static final AppConfig instance = AppConfig._();

  static const defaultWorkerBaseUrl = 'https://bigclerk.workers.dev';
  static const defaultSupabaseUrl =
      'https://wxmgtugqiisnojqbezby.supabase.co';
  static const defaultSupabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Ind4bWd0dWdxaWlzbm9qcWJlemJ5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzgwMTE4NTgsImV4cCI6MjA5MzU4Nzg1OH0.wo1sYZnxBrsjuWvP11luDWkKXesrghMQifM_qVMfZIU';

  /// auto | online | offline
  String mode = 'auto';
  String workerBaseUrl = defaultWorkerBaseUrl;
  String supabaseUrl = defaultSupabaseUrl;
  String supabaseAnonKey = defaultSupabaseAnonKey;
  String studentName = 'Anonymous';

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    mode = p.getString('mode') ?? 'auto';
    workerBaseUrl = p.getString('workerBaseUrl') ?? defaultWorkerBaseUrl;
    supabaseUrl = p.getString('supabaseUrl') ?? defaultSupabaseUrl;
    supabaseAnonKey = p.getString('supabaseAnonKey') ?? defaultSupabaseAnonKey;
    studentName = p.getString('studentName') ?? 'Anonymous';
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('mode', mode);
    await p.setString('workerBaseUrl', workerBaseUrl.trim());
    await p.setString('supabaseUrl', supabaseUrl.trim());
    await p.setString('supabaseAnonKey', supabaseAnonKey.trim());
    await p.setString('studentName', studentName.trim());
  }

  String get workerRoot {
    var u = workerBaseUrl.trim();
    if (u.endsWith('/')) u = u.substring(0, u.length - 1);
    return u;
  }
}

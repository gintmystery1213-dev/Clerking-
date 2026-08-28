import 'package:flutter/material.dart';

import '../services/app_config.dart';
import '../services/case_repository.dart';
import '../services/connectivity_helper.dart';
import '../core/miss_log.dart';
import '../core/quality_loop.dart';
import '../services/worker_api.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _workerCtrl = TextEditingController();
  final _supabaseCtrl = TextEditingController();
  final _keyCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  String _mode = 'auto';
  String _status = '';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final c = AppConfig.instance;
    _workerCtrl.text = c.workerBaseUrl;
    _supabaseCtrl.text = c.supabaseUrl;
    _keyCtrl.text = c.supabaseAnonKey;
    _nameCtrl.text = c.studentName;
    _mode = c.mode;
  }

  @override
  void dispose() {
    _workerCtrl.dispose();
    _supabaseCtrl.dispose();
    _keyCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final c = AppConfig.instance;
    c.workerBaseUrl = _workerCtrl.text.trim();
    c.supabaseUrl = _supabaseCtrl.text.trim();
    c.supabaseAnonKey = _keyCtrl.text.trim();
    c.studentName = _nameCtrl.text.trim().isEmpty ? 'Anonymous' : _nameCtrl.text.trim();
    c.mode = _mode;
    await c.save();
    CaseRepository.instance.clearCache();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved')),
      );
    }
  }

  Future<void> _probe() async {
    setState(() {
      _busy = true;
      _status = 'Checking…';
    });
    await _save();
    try {
      final workerOk = await ConnectivityHelper.instance.workerReachable();
      final sbOk = await ConnectivityHelper.instance.supabaseReachable();
      String health = '';
      if (workerOk) {
        final h = await WorkerApi().health();
        health = ' · engine=${h['engine'] ?? 'ok'} · supabase@worker=${h['supabase']?['status']}';
      }
      setState(() {
        _status =
            'Worker: ${workerOk ? "online" : "unreachable"}\nSupabase: ${sbOk ? "reachable" : "unreachable"}$health';
      });
    } catch (e) {
      setState(() => _status = 'Error: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Connection settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Engine mode', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'auto', label: Text('Auto'), icon: Icon(Icons.sync)),
              ButtonSegment(value: 'online', label: Text('Online'), icon: Icon(Icons.cloud)),
              ButtonSegment(value: 'offline', label: Text('Offline'), icon: Icon(Icons.offline_bolt)),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
          const SizedBox(height: 8),
          Text(
            'Auto uses the Worker when reachable, otherwise the on-device engine.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Student name (for leaderboard)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _workerCtrl,
            decoration: const InputDecoration(
              labelText: 'Cloudflare Worker URL',
              hintText: 'https://bigclerk.<subdomain>.workers.dev',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _supabaseCtrl,
            decoration: const InputDecoration(
              labelText: 'Supabase URL',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _keyCtrl,
            decoration: const InputDecoration(
              labelText: 'Supabase anon key',
              border: OutlineInputBorder(),
            ),
            obscureText: true,
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: const Text('Save'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _probe,
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.network_check),
            label: const Text('Test connection'),
          ),
          if (_status.isNotEmpty) ...[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_status),
              ),
            ),
          ],
          const SizedBox(height: 24),
          Text('Learning loop', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Text(
            'Unmatched questions are stored on device so patterns can be improved later.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () {
              final n = MissLog.instance.snapshot().length;
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text('Miss log ($n)'),
                  content: SizedBox(
                    width: double.maxFinite,
                    child: n == 0
                        ? const Text('No unmatched questions yet.')
                        : ListView.builder(
                            shrinkWrap: true,
                            itemCount: n.clamp(0, 50),
                            itemBuilder: (_, i) {
                              final e = MissLog.instance.snapshot()[i];
                              return ListTile(
                                dense: true,
                                title: Text('${e['message']}'),
                                subtitle: Text('${e['reason']} · ${e['normalised']}'),
                              );
                            },
                          ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () async {
                        await MissLog.instance.clear();
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                      child: const Text('Clear'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              );
            },
            child: const Text('View unmatched questions'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy
                ? null
                : () async {
                    setState(() {
                      _busy = true;
                      _status = 'Running regression…';
                    });
                    try {
                      final report = await runRegression();
                      if (!mounted) return;
                      setState(() {
                        _status = report.toString();
                        _busy = false;
                      });
                    } catch (e) {
                      if (!mounted) return;
                      setState(() {
                        _status = 'Regression error: $e';
                        _busy = false;
                      });
                    }
                  },
            icon: const Icon(Icons.science_outlined),
            label: const Text('Run engine regression'),
          ),
        ],
      ),
    );
  }
}

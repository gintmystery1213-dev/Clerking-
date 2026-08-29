import 'package:flutter/material.dart';

import '../services/app_config.dart';
import '../services/case_repository.dart';
import '../services/connectivity_helper.dart';
import '../core/miss_log.dart';
import '../core/quality_loop.dart';

/// User-facing preferences only.
/// Backend URLs and keys are hard-wired in [AppConfig] and never shown here.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _nameCtrl = TextEditingController();
  String _mode = 'auto';
  String _status = '';
  bool _busy = false;
  bool? _backendOk;

  @override
  void initState() {
    super.initState();
    final c = AppConfig.instance;
    _nameCtrl.text = c.studentName;
    _mode = c.mode;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final c = AppConfig.instance;
    c.studentName =
        _nameCtrl.text.trim().isEmpty ? 'Anonymous' : _nameCtrl.text.trim();
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
      _status = 'Checking connection…';
      _backendOk = null;
    });
    try {
      final workerOk = await ConnectivityHelper.instance.workerReachable();
      final sbOk = await ConnectivityHelper.instance.supabaseReachable();
      final ok = workerOk && sbOk;
      setState(() {
        _backendOk = ok;
        if (ok) {
          _status = 'Connected — online features available';
        } else if (workerOk) {
          _status =
              'Partially connected — some online features may be limited';
        } else {
          _status = 'Offline — using on-device engine only';
        }
      });
    } catch (e) {
      setState(() {
        _backendOk = false;
        _status = 'Unable to reach servers — using on-device engine';
      });
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Engine mode', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'auto',
                label: Text('Auto'),
                icon: Icon(Icons.sync, size: 18),
              ),
              ButtonSegment(
                value: 'online',
                label: Text('Online'),
                icon: Icon(Icons.cloud, size: 18),
              ),
              ButtonSegment(
                value: 'offline',
                label: Text('Offline'),
                icon: Icon(Icons.offline_bolt, size: 18),
              ),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
          const SizedBox(height: 8),
          Text(
            'Auto uses the cloud when reachable, otherwise the on-device engine.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Display name',
              hintText: 'Shown on leaderboard',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.person_outline),
            ),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy
                ? null
                : () async {
                    await _save();
                  },
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Save'),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : _probe,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    _backendOk == true
                        ? Icons.cloud_done_outlined
                        : _backendOk == false
                            ? Icons.cloud_off_outlined
                            : Icons.wifi_tethering,
                  ),
            label: Text(_busy ? 'Checking…' : 'Test connection'),
          ),
          if (_status.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _backendOk == true
                    ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
                    : _backendOk == false
                        ? theme.colorScheme.errorContainer
                            .withValues(alpha: 0.4)
                        : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _status,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: _backendOk == true
                      ? theme.colorScheme.onPrimaryContainer
                      : _backendOk == false
                          ? theme.colorScheme.onErrorContainer
                          : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
          const SizedBox(height: 32),
          Divider(color: theme.colorScheme.outlineVariant),
          const SizedBox(height: 8),
          Text(
            'Learning loop',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            'Unmatched questions are stored on device so patterns can be improved later.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
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
                                subtitle: Text(
                                  '${e['reason']} · ${e['normalised']}',
                                ),
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
                      _backendOk = null;
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

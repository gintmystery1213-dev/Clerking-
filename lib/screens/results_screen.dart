import 'package:flutter/material.dart';

import '../services/session_controller.dart';

class ResultsScreen extends StatefulWidget {
  final SessionController session;

  const ResultsScreen({super.key, required this.session});

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  String _syncStatus = 'Syncing score…';

  @override
  void initState() {
    super.initState();
    _submit();
  }

  Future<void> _submit() async {
    final r = await widget.session.submitScore();
    if (!mounted) return;
    final workerOk = r['worker'] != null;
    final sbOk = r['supabase'] == true;
    setState(() {
      if (workerOk && sbOk) {
        _syncStatus = 'Saved to Worker + Supabase';
      } else if (workerOk) {
        _syncStatus = 'Saved to Worker';
      } else if (sbOk) {
        _syncStatus = 'Saved to Supabase';
      } else {
        _syncStatus = 'Offline — score kept on device only';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final c = session.caseData!;
    final theme = Theme.of(context);
    final max = c.maxScore;
    final pct = max > 0 ? (session.totalScore / max * 100).clamp(0, 100) : 0.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Session summary'),
        automaticallyImplyLeading: false,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            c.patient.avatar ?? '👤',
            style: const TextStyle(fontSize: 48),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            c.patient.name,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            c.primaryDiagnosis,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _syncStatus,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Text(
                    '${session.totalScore}',
                    style: theme.textTheme.displayMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  Text('points  ·  ${pct.toStringAsFixed(0)}% of max ($max)'),
                  if (session.penalties > 0) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Penalties: −${session.penalties}',
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _StatTile(
            label: 'Must-ask covered',
            value: '${session.mustAsked} / ${c.mustAsk.length}',
          ),
          _StatTile(
            label: 'Should-ask covered',
            value: '${session.shouldAsked} / ${c.shouldAsk.length}',
          ),
          _StatTile(
            label: 'Intents unlocked',
            value: '${session.askedIntents.length}',
          ),
          _StatTile(
            label: 'Messages',
            value: '${session.messages.where((m) => m.role != 'system').length}',
          ),
          const SizedBox(height: 12),
          if (c.mustAsk.isNotEmpty) ...[
            Text('Must-ask checklist', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            ...c.mustAsk.map((id) {
              final done = session.askedIntents.contains(id);
              return ListTile(
                dense: true,
                leading: Icon(
                  done ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: done ? Colors.green : theme.colorScheme.outline,
                ),
                title: Text(id),
              );
            }),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () {
              Navigator.of(context).popUntil((r) => r.isFirst);
            },
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Back to home'),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text('Try another case'),
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;

  const _StatTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      trailing: Text(
        value,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
    );
  }
}

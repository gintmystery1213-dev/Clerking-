import 'package:flutter/material.dart';

import '../models/case_model.dart';
import '../services/case_repository.dart';
import 'chat_screen.dart';

class CaseListScreen extends StatefulWidget {
  const CaseListScreen({super.key});

  @override
  State<CaseListScreen> createState() => _CaseListScreenState();
}

class _CaseListScreenState extends State<CaseListScreen> {
  late Future<List<CaseModel>> _future;
  String _difficulty = 'all';

  @override
  void initState() {
    super.initState();
    _future = CaseRepository.instance.loadCases();
  }

  void _reload() {
    CaseRepository.instance.clearCache();
    setState(() {
      _future = CaseRepository.instance.loadCases(forceRefresh: true);
    });
  }

  Color _diffColor(String d) {
    switch (d.toLowerCase()) {
      case 'easy':
        return Colors.green;
      case 'hard':
        return Colors.redAccent;
      default:
        return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cases'),
        actions: [
          IconButton(
            tooltip: 'Refresh from Worker',
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
          PopupMenuButton<String>(
            initialValue: _difficulty,
            onSelected: (v) => setState(() => _difficulty = v),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'all', child: Text('All levels')),
              PopupMenuItem(value: 'easy', child: Text('Easy')),
              PopupMenuItem(value: 'medium', child: Text('Medium')),
              PopupMenuItem(value: 'hard', child: Text('Hard')),
            ],
            icon: const Icon(Icons.filter_list),
          ),
        ],
      ),
      body: FutureBuilder<List<CaseModel>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          var cases = snap.data ?? [];
          if (_difficulty != 'all') {
            cases = cases
                .where((c) => c.difficulty.toLowerCase() == _difficulty)
                .toList();
          }
          if (cases.isEmpty) {
            return const Center(child: Text('No cases found'));
          }
          final source = CaseRepository.instance.lastSource ?? 'assets';
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Chip(
                    avatar: Icon(
                      source == 'worker'
                          ? Icons.cloud_done
                          : Icons.phone_android,
                      size: 16,
                    ),
                    label: Text(
                      source == 'worker'
                          ? 'Cases from Worker'
                          : 'Cases from device',
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: cases.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final c = cases[i];
                    return Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        leading: CircleAvatar(
                          child: Text(c.patient.avatar ?? '👤'),
                        ),
                        title: Text(
                          c.patient.name,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Text(
                              c.presentingComplaint,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              children: [
                                Chip(
                                  label: Text(c.difficulty),
                                  visualDensity: VisualDensity.compact,
                                  backgroundColor: _diffColor(c.difficulty)
                                      .withValues(alpha: 0.15),
                                  side: BorderSide.none,
                                  labelStyle: TextStyle(
                                    color: _diffColor(c.difficulty),
                                    fontSize: 12,
                                  ),
                                ),
                                Chip(
                                  label: Text(c.discipline),
                                  visualDensity: VisualDensity.compact,
                                  side: BorderSide.none,
                                ),
                                if (c.timeLimit != null)
                                  Chip(
                                    label: Text('${c.timeLimit! ~/ 60} min'),
                                    visualDensity: VisualDensity.compact,
                                    side: BorderSide.none,
                                  ),
                              ],
                            ),
                          ],
                        ),
                        isThreeLine: true,
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ChatScreen(caseModel: c),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

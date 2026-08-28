import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/case_model.dart';
import '../models/chat_message.dart';
import '../services/session_controller.dart';
import 'results_screen.dart';

class ChatScreen extends StatefulWidget {
  final CaseModel caseModel;

  const ChatScreen({super.key, required this.caseModel});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final SessionController _session;
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _session = SessionController()..start(widget.caseModel);
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _session.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    _input.clear();
    await _session.sendMessage(text);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent + 80,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _finish() {
    _session.endSession();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ResultsScreen(session: _session),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _session,
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.caseModel.patient.name,
                style: const TextStyle(fontSize: 16),
              ),
              Text(
                widget.caseModel.presentingComplaint,
                style: Theme.of(context).textTheme.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          actions: [
            Consumer<SessionController>(
              builder: (_, s, __) {
                final online = s.lastEngineSource.name == 'worker';
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      online ? Icons.cloud_done_outlined : Icons.offline_bolt_outlined,
                      size: 18,
                      color: online ? Colors.teal : Colors.orange,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${s.totalScore} pts',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 8),
                  ],
                );
              },
            ),
            IconButton(
              tooltip: 'End session',
              onPressed: _finish,
              icon: const Icon(Icons.flag_outlined),
            ),
          ],
        ),
        body: Column(
          children: [
            Consumer<SessionController>(
              builder: (_, s, __) {
                return LinearProgressIndicator(
                  value: s.progressPercent,
                  minHeight: 3,
                );
              },
            ),
            Expanded(
              child: Consumer<SessionController>(
                builder: (context, s, _) {
                  return ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(12),
                    itemCount: s.messages.length,
                    itemBuilder: (_, i) => _Bubble(msg: s.messages[i]),
                  );
                },
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _input,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        decoration: InputDecoration(
                          hintText: 'Ask the patient…',
                          filled: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Consumer<SessionController>(
                      builder: (_, s, __) => FilledButton(
                        onPressed: s.isSending ? null : _send,
                        style: FilledButton.styleFrom(
                          shape: const CircleBorder(),
                          padding: const EdgeInsets.all(14),
                        ),
                        child: s.isSending
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.send_rounded),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final ChatMessage msg;

  const _Bubble({required this.msg});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isStudent = msg.role == 'student';
    final isSystem = msg.role == 'system';

    if (isSystem) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(msg.content, style: theme.textTheme.bodyMedium),
      );
    }

    return Align(
      alignment: isStudent ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.82,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: msg.isDangerous
              ? theme.colorScheme.errorContainer
              : isStudent
                  ? theme.colorScheme.primaryContainer
                  : theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isStudent ? 16 : 4),
            bottomRight: Radius.circular(isStudent ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(msg.content),
            if (msg.score > 0 || msg.pearl != null) ...[
              const SizedBox(height: 6),
              if (msg.score > 0)
                Text(
                  '+${msg.score} pts'
                  '${msg.intentId != null ? ' · ${msg.intentId}' : ''}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              if (msg.pearl != null) ...[
                const SizedBox(height: 4),
                Text(
                  '💡 ${msg.pearl}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class ChatMessage {
  final String role; // 'student' | 'patient' | 'system'
  final String content;
  final String? intentId;
  final String? type;
  final int score;
  final String? pearl;
  final bool isDangerous;
  final DateTime timestamp;

  ChatMessage({
    required this.role,
    required this.content,
    this.intentId,
    this.type,
    this.score = 0,
    this.pearl,
    this.isDangerous = false,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toHistoryMap() => {
        'role': role == 'patient' ? 'assistant' : role,
        'content': content,
        'reply': content,
      };
}

import 'package:hive/hive.dart';
import 'message.dart';

part 'conversation.g.dart';

/// Represents a conversation session with a specific AI provider
@HiveType(typeId: 1)
class Conversation extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String provider; // 'gemini', 'openai', 'deepseek', 'mistral'

  @HiveField(2)
  final String mode; // 'live' or 'standard'

  @HiveField(3)
  final DateTime startTime;

  @HiveField(4)
  DateTime? endTime;

  @HiveField(5)
  List<Message> messages;

  @HiveField(6)
  String? summary;

  Conversation({
    required this.id,
    required this.provider,
    required this.mode,
    required this.startTime,
    this.endTime,
    List<Message>? messages,
    this.summary,
  }) : messages = messages ?? [];

  /// Get preview text for history display
  String? get preview {
    if (messages.isEmpty) return null;

    // Find first AI response
    for (final msg in messages) {
      if (msg.role == 'assistant') {
        return msg.content.length > 100
            ? '${msg.content.substring(0, 100)}...'
            : msg.content;
      }
    }

    // Fallback to first user message
    return messages.first.content.length > 100
        ? '${messages.first.content.substring(0, 100)}...'
        : messages.first.content;
  }

  /// Check if any messages have associated audio
  bool get hasAudio => messages.any((m) => m.audioPath != null);

  /// Get message count
  int get messageCount => messages.length;

  /// Add a message to the conversation
  void addMessage(Message message) {
    messages.add(message);
    save();
  }

  /// End the conversation
  void end() {
    endTime = DateTime.now();
    save();
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'provider': provider,
    'mode': mode,
    'startTime': startTime.toIso8601String(),
    'endTime': endTime?.toIso8601String(),
    'messages': messages.map((m) => m.toJson()).toList(),
    'summary': summary,
  };

  factory Conversation.fromJson(Map<String, dynamic> json) => Conversation(
    id: json['id'] as String,
    provider: json['provider'] as String,
    mode: json['mode'] as String,
    startTime: DateTime.parse(json['startTime'] as String),
    endTime: json['endTime'] != null
        ? DateTime.parse(json['endTime'] as String)
        : null,
    messages: (json['messages'] as List<dynamic>?)
        ?.map((m) => Message.fromJson(m as Map<String, dynamic>))
        .toList(),
    summary: json['summary'] as String?,
  );
}

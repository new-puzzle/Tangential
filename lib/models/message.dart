import 'package:hive/hive.dart';

part 'message.g.dart';

/// Represents a single message in a conversation
@HiveType(typeId: 0)
class Message extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String role; // 'user' or 'assistant'

  @HiveField(2)
  final String content;

  @HiveField(3)
  final DateTime timestamp;

  @HiveField(4)
  final String? audioPath;

  @HiveField(5)
  final String? attachmentPath;

  @HiveField(6)
  final String? attachmentName;

  Message({
    required this.id,
    required this.role,
    required this.content,
    required this.timestamp,
    this.audioPath,
    this.attachmentPath,
    this.attachmentName,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'role': role,
    'content': content,
    'timestamp': timestamp.toIso8601String(),
    'audioPath': audioPath,
    'attachmentPath': attachmentPath,
    'attachmentName': attachmentName,
  };

  factory Message.fromJson(Map<String, dynamic> json) => Message(
    id: json['id'] as String,
    role: json['role'] as String,
    content: json['content'] as String,
    timestamp: DateTime.parse(json['timestamp'] as String),
    audioPath: json['audioPath'] as String?,
    attachmentPath: json['attachmentPath'] as String?,
    attachmentName: json['attachmentName'] as String?,
  );
}

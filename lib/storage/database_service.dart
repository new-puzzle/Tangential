import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/conversation.dart';
import '../models/message.dart';
import '../providers/app_state.dart';

/// Service for managing local storage of conversations and settings.
/// Uses Hive for fast key-value storage.
class DatabaseService {
  static const String _conversationsBoxName = 'conversations';
  static const String _settingsBoxName = 'settings';

  Box<Conversation>? _conversationsBox;
  Box<dynamic>? _settingsBox;

  final _uuid = const Uuid();

  bool get isInitialized => _conversationsBox != null && _settingsBox != null;

  /// Initialize the database
  Future<void> initialize() async {
    if (isInitialized) return;

    try {
      await Hive.initFlutter();

      // Register adapters
      if (!Hive.isAdapterRegistered(0)) {
        Hive.registerAdapter(MessageAdapter());
      }
      if (!Hive.isAdapterRegistered(1)) {
        Hive.registerAdapter(ConversationAdapter());
      }

      // Open boxes
      _conversationsBox = await Hive.openBox<Conversation>(
        _conversationsBoxName,
      );
      _settingsBox = await Hive.openBox<dynamic>(_settingsBoxName);

      debugPrint('Database initialized successfully');
    } catch (e) {
      debugPrint('Error initializing database: $e');
      rethrow;
    }
  }

  /// Create a new conversation
  Future<Conversation> createConversation({
    required AiProvider provider,
    required AiMode mode,
  }) async {
    final conversation = Conversation(
      id: _uuid.v4(),
      provider: provider.name,
      mode: mode.name,
      startTime: DateTime.now(),
    );

    await _conversationsBox?.put(conversation.id, conversation);
    return conversation;
  }

  /// Get all conversations for a provider
  List<Conversation> getConversationsForProvider(AiProvider provider) {
    if (_conversationsBox == null) return [];

    return _conversationsBox!.values
        .where((c) => c.provider == provider.name)
        .toList()
      ..sort((a, b) => b.startTime.compareTo(a.startTime));
  }

  /// Get all conversations
  List<Conversation> getAllConversations() {
    if (_conversationsBox == null) return [];

    return _conversationsBox!.values.toList()
      ..sort((a, b) => b.startTime.compareTo(a.startTime));
  }

  /// Get a specific conversation
  Conversation? getConversation(String id) {
    return _conversationsBox?.get(id);
  }

  /// Add a message to a conversation
  Future<void> addMessage({
    required String conversationId,
    required String role,
    required String content,
    String? audioPath,
    String? attachmentPath,
    String? attachmentName,
  }) async {
    final conversation = _conversationsBox?.get(conversationId);
    if (conversation == null) return;

    final message = Message(
      id: _uuid.v4(),
      role: role,
      content: content,
      timestamp: DateTime.now(),
      audioPath: audioPath,
      attachmentPath: attachmentPath,
      attachmentName: attachmentName,
    );

    conversation.addMessage(message);
  }

  /// End a conversation
  Future<void> endConversation(String conversationId) async {
    final conversation = _conversationsBox?.get(conversationId);
    conversation?.end();
  }

  /// Delete a conversation
  Future<void> deleteConversation(String conversationId) async {
    final conversation = _conversationsBox?.get(conversationId);
    if (conversation == null) return;

    // Delete associated audio files
    for (final message in conversation.messages) {
      if (message.audioPath != null) {
        try {
          await File(message.audioPath!).delete();
        } catch (e) {
          debugPrint('Error deleting audio file: $e');
        }
      }
    }

    await _conversationsBox?.delete(conversationId);
  }

  /// Clear all conversations for a provider
  Future<void> clearHistoryForProvider(AiProvider provider) async {
    if (_conversationsBox == null) return;

    final toDelete = _conversationsBox!.values
        .where((c) => c.provider == provider.name)
        .map((c) => c.id)
        .toList();

    for (final id in toDelete) {
      await deleteConversation(id);
    }
  }

  /// Clear all data
  Future<void> clearAllData() async {
    // Delete all audio files
    final recordings = await _getRecordingsDirectory();
    if (recordings != null && await recordings.exists()) {
      await recordings.delete(recursive: true);
    }

    // Clear boxes
    await _conversationsBox?.clear();
    await _settingsBox?.clear();
  }

  /// Cleanup old audio recordings
  Future<int> cleanupOldRecordings(int retentionDays) async {
    final recordings = await _getRecordingsDirectory();
    if (recordings == null || !await recordings.exists()) return 0;

    final cutoffDate = DateTime.now().subtract(Duration(days: retentionDays));
    int deletedCount = 0;

    await for (final entity in recordings.list()) {
      if (entity is File) {
        final stat = await entity.stat();
        if (stat.modified.isBefore(cutoffDate)) {
          await entity.delete();
          deletedCount++;
        }
      }
    }

    debugPrint('Cleaned up $deletedCount old recordings');
    return deletedCount;
  }

  /// Get the recordings directory
  Future<Directory?> _getRecordingsDirectory() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      return Directory('${appDir.path}/recordings');
    } catch (e) {
      debugPrint('Error getting recordings directory: $e');
      return null;
    }
  }

  /// Get storage usage info
  Future<Map<String, int>> getStorageInfo() async {
    int audioBytes = 0;
    int audioCount = 0;

    final recordings = await _getRecordingsDirectory();
    if (recordings != null && await recordings.exists()) {
      await for (final entity in recordings.list()) {
        if (entity is File) {
          audioBytes += await entity.length();
          audioCount++;
        }
      }
    }

    return {
      'audioBytes': audioBytes,
      'audioCount': audioCount,
      'conversationCount': _conversationsBox?.length ?? 0,
    };
  }

  /// Close the database
  Future<void> close() async {
    await _conversationsBox?.close();
    await _settingsBox?.close();
  }
}

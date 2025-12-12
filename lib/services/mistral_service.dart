import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:mime/mime.dart';
import 'system_prompt.dart';

/// Mistral API service for Whisper STT -> Mistral -> TTS flow.
/// Supports vision/file uploads via Pixtral.
class MistralService {
  final Dio _dio = Dio();
  String? _apiKey;

  static const String _baseUrl = 'https://api.mistral.ai/v1';

  // Conversation history for context
  final List<Map<String, dynamic>> _conversationHistory = [];

  /// Initialize with API key
  void setApiKey(String apiKey) {
    _apiKey = apiKey;
  }

  /// Send a message and get a response
  Future<String?> sendMessage(String message, {File? attachment}) async {
    if (_apiKey == null || _apiKey!.isEmpty) {
      debugPrint('Mistral API key not set');
      return null;
    }

    try {
      // Build message content
      final List<Map<String, dynamic>> content = [];
      bool hasImage = false;

      // Add file attachment if present (Mistral Pixtral supports vision)
      if (attachment != null) {
        final mimeType =
            lookupMimeType(attachment.path) ?? 'application/octet-stream';

        if (mimeType.startsWith('image/')) {
          hasImage = true;
          final bytes = await attachment.readAsBytes();
          final base64Image = base64Encode(bytes);
          content.add({
            'type': 'image_url',
            'image_url': 'data:$mimeType;base64,$base64Image',
          });
        } else {
          // For text files, include content as text
          final textContent = await _tryReadTextFile(attachment);
          if (textContent != null) {
            content.add({
              'type': 'text',
              'text': 'File content:\n$textContent',
            });
          }
        }
      }

      // Add user message
      content.add({'type': 'text', 'text': message});

      // Add to history
      _conversationHistory.add({
        'role': 'user',
        'content': content.length == 1 ? message : content,
      });

      // Build messages with system prompt
      final messages = [
        {'role': 'system', 'content': tangentialSystemPrompt},
        ..._conversationHistory.take(20), // Limit context window
      ];

      // Use pixtral for images, otherwise mistral-large
      final model = hasImage ? 'pixtral-large-latest' : 'mistral-large-latest';

      final response = await _dio.post(
        '$_baseUrl/chat/completions',
        data: {
          'model': model,
          'messages': messages,
          'temperature': 0.7,
          'max_tokens': 500, // Keep responses concise for voice
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer $_apiKey',
            'Content-Type': 'application/json',
          },
          receiveTimeout: const Duration(seconds: 60),
        ),
      );

      if (response.statusCode == 200) {
        final responseText =
            response.data['choices'][0]['message']['content'] as String;

        // Store in history
        _conversationHistory.add({
          'role': 'assistant',
          'content': responseText,
        });

        debugPrint('Mistral response: $responseText');
        return responseText.trim();
      }

      return null;
    } on DioException catch (e) {
      return _handleError(e);
    } catch (e) {
      debugPrint('Error sending message to Mistral: $e');
      return null;
    }
  }

  /// Send a message with an image
  Future<String?> sendMessageWithImage(
    String message,
    Uint8List imageBytes,
    String mimeType,
  ) async {
    if (_apiKey == null || _apiKey!.isEmpty) {
      debugPrint('Mistral API key not set');
      return null;
    }

    try {
      final base64Image = base64Encode(imageBytes);

      final content = [
        {
          'type': 'image_url',
          'image_url': 'data:$mimeType;base64,$base64Image',
        },
        {'type': 'text', 'text': message},
      ];

      _conversationHistory.add({'role': 'user', 'content': content});

      final messages = [
        {'role': 'system', 'content': tangentialSystemPrompt},
        ..._conversationHistory.take(20),
      ];

      final response = await _dio.post(
        '$_baseUrl/chat/completions',
        data: {
          'model': 'pixtral-large-latest',
          'messages': messages,
          'temperature': 0.7,
          'max_tokens': 500,
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer $_apiKey',
            'Content-Type': 'application/json',
          },
        ),
      );

      if (response.statusCode == 200) {
        final responseText =
            response.data['choices'][0]['message']['content'] as String;

        _conversationHistory.add({
          'role': 'assistant',
          'content': responseText,
        });

        return responseText.trim();
      }

      return null;
    } catch (e) {
      debugPrint('Error sending image to Mistral: $e');
      return null;
    }
  }

  /// Get conversation history
  List<Map<String, dynamic>> get conversationHistory =>
      List.unmodifiable(_conversationHistory);

  /// Clear conversation history
  void clearHistory() {
    _conversationHistory.clear();
    debugPrint('Mistral conversation history cleared');
  }

  /// Try to read a file as text
  Future<String?> _tryReadTextFile(File file) async {
    try {
      return await file.readAsString();
    } catch (e) {
      return null;
    }
  }

  /// Handle API errors
  String? _handleError(DioException e) {
    final statusCode = e.response?.statusCode;

    if (statusCode == 429) {
      return "I'm getting a lot of requests right now. Let me catch my breath - try again in a moment, or switch to another AI.";
    } else if (statusCode == 401) {
      return "There seems to be an issue with my connection. Please check the API key in settings.";
    }

    debugPrint('Mistral API error: ${e.message}');
    return null;
  }
}

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:mime/mime.dart';
import 'system_prompt.dart';

/// Gemini Flash service for file uploads and standard STT -> API -> TTS flow.
/// Uses google_generative_ai package for Gemini 2.5 Flash model.
class GeminiFlashService {
  GenerativeModel? _model;
  ChatSession? _chatSession;
  String? _apiKey;

  // Conversation history for context
  final List<Map<String, String>> _conversationHistory = [];

  bool get isInitialized => _model != null;

  /// Initialize with API key
  void initialize(String apiKey) {
    _apiKey = apiKey;
    _model = GenerativeModel(
      model: 'gemini-2.5-flash-preview-05-20',
      apiKey: apiKey,
      systemInstruction: Content.system(tangentialSystemPrompt),
      generationConfig: GenerationConfig(
        temperature: 0.7,
        topP: 0.9,
        topK: 40,
        maxOutputTokens: 500, // Keep responses concise for voice
      ),
      safetySettings: [
        SafetySetting(HarmCategory.harassment, HarmBlockThreshold.none),
        SafetySetting(HarmCategory.hateSpeech, HarmBlockThreshold.none),
        SafetySetting(HarmCategory.sexuallyExplicit, HarmBlockThreshold.medium),
        SafetySetting(HarmCategory.dangerousContent, HarmBlockThreshold.medium),
      ],
    );

    // Start a new chat session
    _chatSession = _model!.startChat(history: []);
    debugPrint('Gemini Flash service initialized');
  }

  /// Send a text message and get a response
  Future<String?> sendMessage(String message, {File? attachment}) async {
    if (_model == null || _chatSession == null) {
      debugPrint('Gemini Flash not initialized');
      return null;
    }

    try {
      // Build content parts
      final List<Part> parts = [];

      // Add file attachment if present
      if (attachment != null) {
        final mimeType =
            lookupMimeType(attachment.path) ?? 'application/octet-stream';
        final bytes = await attachment.readAsBytes();

        if (mimeType.startsWith('image/')) {
          parts.add(DataPart(mimeType, bytes));
        } else if (mimeType == 'application/pdf') {
          // For PDFs, we can use inline data
          parts.add(DataPart(mimeType, bytes));
        } else {
          // For other files, include as context in the message
          final textContent = await _tryReadTextFile(attachment);
          if (textContent != null) {
            parts.add(TextPart('File content:\n$textContent\n\n'));
          }
        }
      }

      // Add the user message
      parts.add(TextPart(message));

      // Send message to Gemini
      final response = await _chatSession!.sendMessage(Content.multi(parts));
      final responseText = response.text?.trim();

      if (responseText != null && responseText.isNotEmpty) {
        // Store in history
        _conversationHistory.add({'role': 'user', 'content': message});
        _conversationHistory.add({
          'role': 'assistant',
          'content': responseText,
        });

        debugPrint('Gemini response: $responseText');
        return responseText;
      }

      return null;
    } on GenerativeAIException catch (e) {
      debugPrint('Gemini API error: ${e.message}');
      return _handleError(e);
    } catch (e) {
      debugPrint('Error sending message to Gemini: $e');
      return null;
    }
  }

  /// Send a message with an image
  Future<String?> sendMessageWithImage(
    String message,
    Uint8List imageBytes,
    String mimeType,
  ) async {
    if (_model == null) {
      debugPrint('Gemini Flash not initialized');
      return null;
    }

    try {
      final response = await _model!.generateContent([
        Content.multi([DataPart(mimeType, imageBytes), TextPart(message)]),
      ]);

      final responseText = response.text?.trim();
      if (responseText != null && responseText.isNotEmpty) {
        _conversationHistory.add({
          'role': 'user',
          'content': '[Image] $message',
        });
        _conversationHistory.add({
          'role': 'assistant',
          'content': responseText,
        });
        return responseText;
      }

      return null;
    } catch (e) {
      debugPrint('Error sending image to Gemini: $e');
      return null;
    }
  }

  /// Stream response for longer answers
  Stream<String> streamMessage(String message) async* {
    if (_model == null || _chatSession == null) {
      return;
    }

    try {
      final response = _chatSession!.sendMessageStream(Content.text(message));

      final buffer = StringBuffer();
      await for (final chunk in response) {
        final text = chunk.text;
        if (text != null) {
          buffer.write(text);
          yield text;
        }
      }

      // Store complete response in history
      final fullResponse = buffer.toString().trim();
      if (fullResponse.isNotEmpty) {
        _conversationHistory.add({'role': 'user', 'content': message});
        _conversationHistory.add({
          'role': 'assistant',
          'content': fullResponse,
        });
      }
    } catch (e) {
      debugPrint('Error streaming from Gemini: $e');
    }
  }

  /// Get conversation history
  List<Map<String, String>> get conversationHistory =>
      List.unmodifiable(_conversationHistory);

  /// Clear conversation history and start fresh
  void clearHistory() {
    _conversationHistory.clear();
    if (_model != null) {
      _chatSession = _model!.startChat(history: []);
    }
    debugPrint('Gemini conversation history cleared');
  }

  /// Try to read a file as text
  Future<String?> _tryReadTextFile(File file) async {
    try {
      return await file.readAsString();
    } catch (e) {
      return null;
    }
  }

  /// Handle API errors and return user-friendly messages
  String? _handleError(GenerativeAIException e) {
    final message = e.message.toLowerCase();

    if (message.contains('quota') || message.contains('rate')) {
      return "I'm getting a lot of requests right now. Let me catch my breath - try again in a moment, or switch to another AI.";
    } else if (message.contains('safety')) {
      return "I had trouble with that response. Could you rephrase your question?";
    } else if (message.contains('api key')) {
      return "There seems to be an issue with my connection. Please check the API key in settings.";
    }

    return null;
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'system_prompt.dart';

/// Gemini Live API service for real-time bidirectional voice conversation.
/// Uses WebSocket for streaming audio input/output with interruption support.
class GeminiLiveService {
  WebSocketChannel? _channel;
  String? _apiKey;
  bool _isConnected = false;
  bool _isListening = false;
  bool _isDisconnecting = false;

  // Callbacks
  Function(String)? onTranscript;
  Function(String)? onResponse;
  Function(Uint8List)? onAudio;
  VoidCallback? onConnected;
  VoidCallback? onDisconnected;
  Function(String)? onError;
  VoidCallback? onInterrupted;

  bool get isConnected => _isConnected;
  bool get isListening => _isListening;

  void setApiKey(String apiKey) {
    _apiKey = apiKey;
  }

  /// Connect to Gemini Live API
  Future<bool> connect() async {
    if (_apiKey == null || _apiKey!.isEmpty) {
      onError?.call('Gemini API key not set');
      return false;
    }

    if (_isConnected) return true;

    try {
      final uri = Uri.parse(
        'wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1alpha.GenerativeService.BidiGenerateContent'
        '?key=$_apiKey',
      );

      _channel = WebSocketChannel.connect(uri);
      await _channel!.ready;
      _isConnected = true;
      _isDisconnecting = false;

      await _sendSetupMessage();

      _channel!.stream.listen(
        _handleMessage,
        onError: (error) {
          debugPrint('Gemini Live WebSocket error: $error');
          onError?.call('Connection error: $error');
          disconnect();
        },
        onDone: () {
          debugPrint('Gemini Live WebSocket closed');
          disconnect();
        },
      );

      onConnected?.call();
      debugPrint('Connected to Gemini Live API');
      return true;
    } catch (e) {
      debugPrint('Error connecting to Gemini Live: $e');
      onError?.call('Failed to connect: $e');
      _isConnected = false;
      return false;
    }
  }

  Future<void> _sendSetupMessage() async {
    final setupMessage = {
      'setup': {
        'model': 'models/gemini-2.0-flash-live-preview', // Use a valid, current model
        'generationConfig': {
          'responseModalities': ['AUDIO', 'TEXT'],
          'speechConfig': {
            'voiceConfig': {
              'prebuiltVoiceConfig': {'voiceName': 'Kore'},
            },
          },
        },
        'systemInstruction': {
          'parts': [
            {'text': tangentialSystemPrompt},
          ],
        },
      },
    };

    _channel?.sink.add(jsonEncode(setupMessage));
  }

  void _handleMessage(dynamic message) {
    try {
      if (message is String) {
        final data = jsonDecode(message) as Map<String, dynamic>;

        if (data.containsKey('serverContent')) {
          final serverContent = data['serverContent'] as Map<String, dynamic>;

          if (serverContent['interrupted'] == true) {
            onInterrupted?.call();
            return;
          }

          if (serverContent.containsKey('modelTurn')) {
            final modelTurn =
                serverContent['modelTurn'] as Map<String, dynamic>;
            final parts = modelTurn['parts'] as List<dynamic>?;

            if (parts != null) {
              for (final part in parts) {
                if (part is Map<String, dynamic>) {
                  if (part.containsKey('text')) {
                    onResponse?.call(part['text'] as String);
                  }
                  if (part.containsKey('inlineData')) {
                    final inlineData =
                        part['inlineData'] as Map<String, dynamic>;
                    final audioData = inlineData['data'] as String?;
                    if (audioData != null) {
                      final audioBytes = base64Decode(audioData);
                      onAudio?.call(audioBytes);
                    }
                  }
                }
              }
            }
          }

          if (serverContent['turnComplete'] == true) {
            _isListening = true;
          }
        }

        if (data.containsKey('clientContent')) {
          final clientContent = data['clientContent'] as Map<String, dynamic>;
          if (clientContent.containsKey('transcript')) {
            onTranscript?.call(clientContent['transcript'] as String);
          }
        }
      } else if (message is List<int>) {
        onAudio?.call(Uint8List.fromList(message));
      }
    } catch (e) {
      debugPrint('Error handling Gemini Live message: $e');
    }
  }

  void sendAudio(Uint8List audioData) {
    if (!_isConnected || _channel == null) return;

    final message = {
      'realtimeInput': {
        'mediaChunks': [
          {'mimeType': 'audio/pcm;rate=16000', 'data': base64Encode(audioData)},
        ],
      },
    };

    _channel!.sink.add(jsonEncode(message));
  }

  void sendText(String text) {
    if (!_isConnected || _channel == null) return;

    final message = {
      'clientContent': {
        'turns': [
          {
            'role': 'user',
            'parts': [
              {'text': text},
            ],
          },
        ],
        'turnComplete': true,
      },
    };

    _channel!.sink.add(jsonEncode(message));
    _isListening = false;
  }

  void endTurn() {
    if (!_isConnected || _channel == null) return;

    final message = {
      'clientContent': {'turnComplete': true},
    };

    _channel!.sink.add(jsonEncode(message));
    _isListening = false;
  }

  void interrupt() {
    sendAudio(Uint8List(0));
    onInterrupted?.call();
  }

  /// Disconnect from Gemini Live - idempotent
  void disconnect() {
    if (_isDisconnecting || !_isConnected) return;
    _isDisconnecting = true;

    try {
      _channel?.sink.close();
    } catch (e) {
      // Ignore close errors, channel may already be gone
    }
    _channel = null;
    _isConnected = false;
    _isListening = false;
    // DO NOT reset _isDisconnecting. It's reset in connect().
    debugPrint('Disconnected from Gemini Live API');
    onDisconnected?.call();
  }

  void dispose() {
    disconnect();
  }
}

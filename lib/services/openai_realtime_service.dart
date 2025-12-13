import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'system_prompt.dart';

/// OpenAI Realtime API service for real-time bidirectional voice conversation.
class OpenAiRealtimeService {
  WebSocketChannel? _channel;
  String? _apiKey;
  bool _isConnected = false;
  bool _isDisconnecting = false;

  // Callbacks
  Function(String)? onTranscript;
  Function(String)? onResponse;
  Function(Uint8List)? onAudio;
  VoidCallback? onConnected;
  VoidCallback? onDisconnected;
  Function(String)? onError;
  VoidCallback? onAiDone;

  bool get isConnected => _isConnected;

  void setApiKey(String apiKey) {
    _apiKey = apiKey;
  }

  /// Connect to OpenAI Realtime API
  Future<bool> connect() async {
    if (_apiKey == null || _apiKey!.isEmpty) {
      onError?.call('OpenAI API key not set');
      return false;
    }

    if (_isConnected) return true;

    try {
      final uri = Uri.parse(
        'wss://api.openai.com/v1/realtime?model=gpt-4o-realtime-preview-2024-12-17',
      );

      _channel = WebSocketChannel.connect(
        uri,
        protocols: [
          'realtime',
          'openai-insecure-api-key.$_apiKey',
          'openai-beta.realtime-v1',
        ],
      );

      await _channel!.ready;
      _isConnected = true;
      _isDisconnecting = false;

      await _sendSessionConfig();

      _channel!.stream.listen(
        _handleMessage,
        onError: (error) {
          debugPrint('OpenAI Realtime WebSocket error: $error');
          onError?.call('Connection error: $error');
          disconnect();
        },
        onDone: () {
          debugPrint('OpenAI Realtime WebSocket closed');
          disconnect();
        },
      );

      onConnected?.call();
      debugPrint('Connected to OpenAI Realtime API');
      return true;
    } catch (e) {
      debugPrint('Error connecting to OpenAI Realtime: $e');
      onError?.call('Failed to connect: $e');
      _isConnected = false;
      return false;
    }
  }

  Future<void> _sendSessionConfig() async {
    final config = {
      'type': 'session.update',
      'session': {
        'modalities': ['text', 'audio'],
        'instructions': tangentialSystemPrompt,
        'voice': 'alloy',
        'input_audio_format': 'pcm16',
        'output_audio_format': 'pcm16',
        'input_audio_transcription': {'model': 'whisper-1'},
        'turn_detection': {
          'type': 'server_vad',
          'threshold': 0.5,
          'prefix_padding_ms': 300,
          'silence_duration_ms': 500,
        },
      },
    };

    _channel?.sink.add(jsonEncode(config));
  }

  void _handleMessage(dynamic message) {
    try {
      if (message is! String) return;

      final data = jsonDecode(message) as Map<String, dynamic>;
      final type = data['type'] as String?;

      switch (type) {
        case 'conversation.item.input_audio_transcription.completed':
          final transcript = data['transcript'] as String?;
          if (transcript != null && transcript.isNotEmpty) {
            onTranscript?.call(transcript);
          }
          break;

        case 'response.audio_transcript.delta':
          final delta = data['delta'] as String?;
          if (delta != null) {
            onResponse?.call(delta);
          }
          break;

        case 'response.audio.delta':
          final audioData = data['delta'] as String?;
          if (audioData != null) {
            final audioBytes = base64Decode(audioData);
            onAudio?.call(audioBytes);
          }
          break;

        case 'response.done':
          onAiDone?.call();
          break;

        case 'error':
          final error = data['error'] as Map<String, dynamic>?;
          final errorMsg = error?['message'] as String? ?? 'Unknown error';
          onError?.call(errorMsg);
          break;
      }
    } catch (e) {
      debugPrint('Error handling OpenAI Realtime message: $e');
    }
  }

  void sendAudio(Uint8List audioData) {
    if (!_isConnected || _channel == null) return;

    final message = {
      'type': 'input_audio_buffer.append',
      'audio': base64Encode(audioData),
    };

    _channel!.sink.add(jsonEncode(message));
  }

  void sendText(String text) {
    if (!_isConnected || _channel == null) return;

    final message = {
      'type': 'conversation.item.create',
      'item': {
        'type': 'message',
        'role': 'user',
        'content': [
          {'type': 'input_text', 'text': text},
        ],
      },
    };

    _channel!.sink.add(jsonEncode(message));

    // Trigger response
    _channel!.sink.add(jsonEncode({'type': 'response.create'}));
  }

  void commitAudio() {
    if (!_isConnected || _channel == null) return;
    _channel!.sink.add(jsonEncode({'type': 'input_audio_buffer.commit'}));
    _channel!.sink.add(jsonEncode({'type': 'response.create'}));
  }

  void interrupt() {
    if (!_isConnected || _channel == null) return;
    _channel!.sink.add(jsonEncode({'type': 'response.cancel'}));
  }

  /// Disconnect - idempotent
  void disconnect() {
    if (_isDisconnecting || !_isConnected) return;
    _isDisconnecting = true;

    try {
      _channel?.sink.close();
    } catch (e) {
      // Ignore close errors
    }
    _channel = null;
    _isConnected = false;
    // DO NOT reset _isDisconnecting. It is reset in connect().
    debugPrint('Disconnected from OpenAI Realtime API');
    onDisconnected?.call();
  }

  void dispose() {
    disconnect();
  }
}

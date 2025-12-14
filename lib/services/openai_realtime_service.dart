import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as ws_status;
import 'system_prompt.dart';

/// OpenAI Realtime API service for real-time bidirectional voice conversation.
class OpenAiRealtimeService {
  WebSocketChannel? _channel;
  StreamSubscription? _streamSubscription;
  String? _apiKey;
  bool _isConnected = false;
  bool _sessionConfigured = false;

  // Buffer for accumulating response text
  final StringBuffer _responseBuffer = StringBuffer();

  // Callbacks
  Function(String)? onTranscript;
  Function(String)? onResponse;
  Function(Uint8List)? onAudio;
  VoidCallback? onConnected;
  VoidCallback? onDisconnected;
  Function(String)? onError;
  VoidCallback? onAiDone;

  bool get isConnected => _isConnected && _sessionConfigured;

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

    // Clean up any previous connection
    _cleanup();

    try {
      // OpenAI Realtime API endpoint
      final uri = Uri.parse(
        'wss://api.openai.com/v1/realtime?model=gpt-4o-realtime-preview-2024-12-17',
      );

      debugPrint('OpenAI Realtime: Connecting to WebSocket...');

      // Use protocol-based authentication (required for WebSocket in most environments)
      _channel = WebSocketChannel.connect(
        uri,
        protocols: [
          'realtime',
          'openai-insecure-api-key.$_apiKey',
          'openai-beta.realtime-v1',
        ],
      );

      // Wait for connection with timeout
      await _channel!.ready.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException('WebSocket connection timed out');
        },
      );

      _isConnected = true;
      _sessionConfigured = false;
      debugPrint('OpenAI Realtime: WebSocket connected');

      // Set up completer for session configuration confirmation
      final completer = Completer<bool>();

      _streamSubscription = _channel!.stream.listen(
        (message) {
          _handleMessage(message, completer);
        },
        onError: (error) {
          debugPrint('OpenAI Realtime WebSocket error: $error');
          if (!completer.isCompleted) {
            completer.complete(false);
          }
          onError?.call('Connection error: $error');
          _cleanup();
          onDisconnected?.call();
        },
        onDone: () {
          debugPrint('OpenAI Realtime WebSocket closed by server');
          if (!completer.isCompleted) {
            completer.complete(false);
          }
          final wasConnected = _isConnected;
          _cleanup();
          if (wasConnected) {
            onDisconnected?.call();
          }
        },
        cancelOnError: false,
      );

      // Send session configuration
      _sendSessionConfig();

      // Wait for session.created or session.updated confirmation
      final configSuccess = await completer.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint('OpenAI Realtime: Session config timed out');
          return false;
        },
      );

      if (!configSuccess) {
        debugPrint('OpenAI Realtime: Session configuration failed');
        _cleanup();
        return false;
      }

      _sessionConfigured = true;
      onConnected?.call();
      debugPrint('OpenAI Realtime: Fully connected and configured');
      return true;
    } catch (e) {
      debugPrint('Error connecting to OpenAI Realtime: $e');
      onError?.call('Failed to connect: $e');
      _cleanup();
      return false;
    }
  }

  void _sendSessionConfig() {
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

    debugPrint('OpenAI Realtime: Sending session config');
    _channel?.sink.add(jsonEncode(config));
  }

  void _cleanup() {
    _streamSubscription?.cancel();
    _streamSubscription = null;
    try {
      _channel?.sink.close(ws_status.normalClosure);
    } catch (e) {
      // Ignore close errors
    }
    _channel = null;
    _isConnected = false;
    _sessionConfigured = false;
  }

  void _handleMessage(dynamic message, [Completer<bool>? setupCompleter]) {
    try {
      if (message is! String) return;

      final data = jsonDecode(message) as Map<String, dynamic>;
      final type = data['type'] as String?;

      debugPrint('OpenAI Realtime received: $type');

      switch (type) {
        case 'session.created':
        case 'session.updated':
          // Session is ready
          debugPrint('OpenAI Realtime: Session confirmed');
          if (setupCompleter != null && !setupCompleter.isCompleted) {
            setupCompleter.complete(true);
          }
          break;

        case 'conversation.item.input_audio_transcription.completed':
          final transcript = data['transcript'] as String?;
          if (transcript != null && transcript.isNotEmpty) {
            onTranscript?.call(transcript);
          }
          break;

        case 'response.audio_transcript.delta':
          // Accumulate text deltas instead of sending each word
          final delta = data['delta'] as String?;
          if (delta != null) {
            _responseBuffer.write(delta);
          }
          break;

        case 'response.audio.delta':
          final audioData = data['delta'] as String?;
          if (audioData != null) {
            final audioBytes = base64Decode(audioData);
            onAudio?.call(audioBytes);
          }
          break;

        case 'response.audio_transcript.done':
          // Full transcript complete - send the accumulated text
          final transcript = data['transcript'] as String?;
          if (transcript != null && transcript.isNotEmpty) {
            onResponse?.call(transcript);
          } else if (_responseBuffer.isNotEmpty) {
            onResponse?.call(_responseBuffer.toString());
          }
          _responseBuffer.clear();
          break;

        case 'response.done':
          // Ensure any remaining buffered text is sent
          if (_responseBuffer.isNotEmpty) {
            onResponse?.call(_responseBuffer.toString());
            _responseBuffer.clear();
          }
          onAiDone?.call();
          break;

        case 'error':
          final error = data['error'] as Map<String, dynamic>?;
          final errorMsg = error?['message'] as String? ?? 'Unknown error';
          final errorCode = error?['code'] as String?;
          debugPrint('OpenAI Realtime error: $errorCode - $errorMsg');
          onError?.call(errorMsg);
          if (setupCompleter != null && !setupCompleter.isCompleted) {
            setupCompleter.complete(false);
          }
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

  /// Disconnect from OpenAI Realtime
  void disconnect() {
    if (!_isConnected && _channel == null) return;

    debugPrint('OpenAI Realtime: Disconnecting...');
    final wasConnected = _isConnected;
    _cleanup();

    if (wasConnected) {
      onDisconnected?.call();
    }
    debugPrint('OpenAI Realtime: Disconnected');
  }

  void dispose() {
    _cleanup();
  }
}

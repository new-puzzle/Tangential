import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as ws_status;
import 'system_prompt.dart';

/// Gemini Live API service for real-time bidirectional voice conversation.
/// Uses WebSocket for streaming audio input/output with interruption support.
class GeminiLiveService {
  WebSocketChannel? _channel;
  StreamSubscription? _streamSubscription;
  String? _apiKey;
  bool _isConnected = false;
  bool _isListening = false;
  bool _setupComplete = false;
  
  // Health monitoring
  DateTime? _lastMessageReceived;
  DateTime? get lastMessageReceived => _lastMessageReceived;

  // Buffer for accumulating response text
  final StringBuffer _responseBuffer = StringBuffer();

  // Callbacks
  Function(String)? onTranscript;
  Function(String)? onResponse;
  Function(Uint8List)? onAudio;
  VoidCallback? onConnected;
  VoidCallback? onDisconnected;
  Function(String)? onError;
  VoidCallback? onInterrupted;
  VoidCallback? onTurnComplete;

  String _voice = 'Kore';

  bool get isConnected => _isConnected && _setupComplete;
  bool get isListening => _isListening;

  void setApiKey(String apiKey) {
    _apiKey = apiKey;
  }

  void setVoice(String voice) {
    _voice = voice;
  }

  /// Connect to Gemini Live API
  Future<bool> connect() async {
    if (_apiKey == null || _apiKey!.isEmpty) {
      onError?.call('Gemini API key not set');
      return false;
    }

    if (_isConnected) return true;

    // Clean up any previous connection state
    _cleanup();

    try {
      // Gemini Live API WebSocket endpoint
      final uri = Uri.parse(
        'wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent'
        '?key=$_apiKey',
      );

      debugPrint('Gemini Live: Connecting to WebSocket...');
      _channel = WebSocketChannel.connect(uri);

      // Wait for connection with timeout
      await _channel!.ready.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException('WebSocket connection timed out');
        },
      );

      _isConnected = true;
      _setupComplete = false;
      debugPrint('Gemini Live: WebSocket connected, sending setup...');

      // Set up stream listener BEFORE sending setup message
      final completer = Completer<bool>();

      _streamSubscription = _channel!.stream.listen(
        (message) {
          _handleMessage(message, completer);
        },
        onError: (error) {
          debugPrint('Gemini Live WebSocket error: $error');
          if (!completer.isCompleted) {
            completer.complete(false);
          }
          onError?.call('Connection error: $error');
          _cleanup();
          onDisconnected?.call();
        },
        onDone: () {
          // Try to get close code/reason
          final closeCode = _channel?.closeCode;
          final closeReason = _channel?.closeReason;
          debugPrint(
            'Gemini Live WebSocket closed by server - code: $closeCode, reason: $closeReason',
          );
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

      // Send setup message
      _sendSetupMessage();

      // Wait for setup confirmation with timeout
      final setupSuccess = await completer.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint('Gemini Live: Setup confirmation timed out');
          return false;
        },
      );

      if (!setupSuccess) {
        debugPrint('Gemini Live: Setup failed');
        _cleanup();
        return false;
      }

      _setupComplete = true;
      onConnected?.call();
      debugPrint('Gemini Live: Fully connected and ready');
      return true;
    } catch (e) {
      debugPrint('Error connecting to Gemini Live: $e');
      onError?.call('Failed to connect: $e');
      _cleanup();
      return false;
    }
  }

  void _sendSetupMessage() {
    final setupMessage = {
      'setup': {
        'model': 'models/gemini-2.5-flash-native-audio-preview-09-2025',
        'generationConfig': {
          'responseModalities': ['AUDIO'],
          'temperature': 0.7,
          'topP': 0.95,
          'maxOutputTokens': 8192,
          'speechConfig': {
            'voiceConfig': {
              'prebuiltVoiceConfig': {'voiceName': _voice},
            },
          },
        },
        'systemInstruction': {
          'parts': [
            {'text': tangentialSystemPrompt},
          ],
          'role': 'user',
        },
        'outputAudioTranscription': {},
      },
    };

    final jsonStr = jsonEncode(setupMessage);
    debugPrint('Gemini Live: Sending setup: $jsonStr');
    _channel?.sink.add(jsonStr);
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
    _isListening = false;
    _setupComplete = false;
  }

  void _handleMessage(dynamic message, [Completer<bool>? setupCompleter]) {
    // Update health monitoring timestamp
    _lastMessageReceived = DateTime.now();
    
    try {
      // Convert message to string - Gemini sends binary frames containing JSON
      String? messageStr;
      if (message is String) {
        messageStr = message;
      } else if (message is List<int>) {
        // Try to decode as UTF-8 JSON first
        try {
          messageStr = utf8.decode(message);
        } catch (e) {
          // Not UTF-8, treat as raw audio
          debugPrint('Gemini Live: Raw audio bytes: ${message.length}');
          onAudio?.call(Uint8List.fromList(message));
          return;
        }
      }

      if (messageStr == null) {
        debugPrint('Gemini Live: Unknown message type: ${message.runtimeType}');
        return;
      }

      // Try to parse as JSON
      Map<String, dynamic> data;
      try {
        data = jsonDecode(messageStr) as Map<String, dynamic>;
      } catch (e) {
        debugPrint('Gemini Live: Non-JSON message: $messageStr');
        return;
      }

      debugPrint('Gemini Live received keys: ${data.keys.toList()}');

      // Check for setup completion response
      if (data.containsKey('setupComplete')) {
        debugPrint('Gemini Live: Setup complete confirmed!');
        if (setupCompleter != null && !setupCompleter.isCompleted) {
          setupCompleter.complete(true);
        }
        _isListening = true;
        return;
      }

      // Check for errors
      if (data.containsKey('error')) {
        final error = data['error'] as Map<String, dynamic>?;
        final errorMsg = error?['message'] as String? ?? 'Unknown error';
        debugPrint('Gemini Live error: $errorMsg');
        onError?.call(errorMsg);
        if (setupCompleter != null && !setupCompleter.isCompleted) {
          setupCompleter.complete(false);
        }
        return;
      }

      if (data.containsKey('serverContent')) {
        // If we get serverContent, setup must be complete
        if (setupCompleter != null && !setupCompleter.isCompleted) {
          setupCompleter.complete(true);
        }

        final serverContent = data['serverContent'] as Map<String, dynamic>;

        if (serverContent['interrupted'] == true) {
          onInterrupted?.call();
          return;
        }

        if (serverContent.containsKey('modelTurn')) {
          final modelTurn = serverContent['modelTurn'] as Map<String, dynamic>;
          final parts = modelTurn['parts'] as List<dynamic>?;

          if (parts != null) {
            for (final part in parts) {
              if (part is Map<String, dynamic>) {
                // DON'T show text from modelTurn - that's internal thinking
                // The actual spoken transcript comes from outputAudioTranscription
                if (part.containsKey('inlineData')) {
                  final inlineData = part['inlineData'] as Map<String, dynamic>;
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

        // Handle audio transcription (what the AI actually said)
        // Accumulate text until turn is complete
        if (serverContent.containsKey('outputTranscription')) {
          final transcription =
              serverContent['outputTranscription'] as Map<String, dynamic>?;
          final text = transcription?['text'] as String?;
          if (text != null && text.isNotEmpty) {
            _responseBuffer.write(text);
          }
        }

        if (serverContent['turnComplete'] == true) {
          _isListening = true;
          // Send accumulated transcript when turn completes
          if (_responseBuffer.isNotEmpty) {
            onResponse?.call(_responseBuffer.toString());
            _responseBuffer.clear();
          }
          onTurnComplete?.call();
        }
      }

      if (data.containsKey('clientContent')) {
        final clientContent = data['clientContent'] as Map<String, dynamic>;
        if (clientContent.containsKey('transcript')) {
          onTranscript?.call(clientContent['transcript'] as String);
        }
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

  /// Disconnect from Gemini Live
  void disconnect() {
    if (!_isConnected && _channel == null) return;

    debugPrint('Gemini Live: Disconnecting...');
    final wasConnected = _isConnected;
    _cleanup();

    if (wasConnected) {
      onDisconnected?.call();
    }
    debugPrint('Gemini Live: Disconnected');
  }

  void dispose() {
    _cleanup();
  }
}

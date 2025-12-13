import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'audio_handler.dart';
import 'background_service.dart';
import 'recording_service.dart';
import 'tts_service.dart';
import 'whisper_service.dart';
import 'gemini_flash_service.dart';
import 'gemini_live_service.dart';
import 'openai_realtime_service.dart';
import 'openai_service.dart';
import 'deepseek_service.dart';
import 'mistral_service.dart';
import 'pcm_audio_player.dart';
import '../providers/app_state.dart';

/// Orchestrates the entire conversation flow.
/// - Gemini Live & OpenAI Realtime: Native bidirectional audio via WebSocket
/// - Others (Gemini Flash, GPT-4o, Deepseek, Mistral): VAD + Whisper STT + TTS
class ConversationManager {
  final AppState appState;

  // Core services
  late RecordingService _recordingService;
  late TtsService _ttsService;
  late WhisperService _whisperService;

  // AI Services
  late GeminiFlashService _geminiFlashService;
  late GeminiLiveService _geminiLiveService;
  late OpenAiRealtimeService _openaiRealtimeService;
  late OpenAiService _openaiService;
  late DeepseekService _deepseekService;
  late MistralService _mistralService;
  
  // PCM Audio Player for realtime modes
  late PcmAudioPlayer _pcmPlayer;

  // State
  bool _isRunning = false;
  bool _isProcessing = false;
  bool _isSpeaking = false;

  // Voice Activity Detection (for standard modes only)
  Timer? _vadTimer;
  bool _hasDetectedSpeech = false;
  int _silenceCount = 0;
  static const int _silenceThreshold = 8; // ~1.6 seconds of silence
  static const double _speechThreshold = 0.075;

  // Callbacks
  Function(String)? onUserTranscript;
  Function(String)? onAiResponse;
  Function(ConversationState)? onStateChanged;
  Function(String)? onError;

  ConversationManager({required this.appState}) {
    _initializeServices();
  }

  void _initializeServices() {
    _recordingService = RecordingService();
    _ttsService = TtsService();
    _whisperService = WhisperService();

    _geminiFlashService = GeminiFlashService();
    _geminiLiveService = GeminiLiveService();
    _openaiRealtimeService = OpenAiRealtimeService();
    _openaiService = OpenAiService();
    _deepseekService = DeepseekService();
    _mistralService = MistralService();
    
    // Initialize PCM player for smooth audio playback
    _pcmPlayer = PcmAudioPlayer();
    _pcmPlayer.setSampleRate(24000); // Both Gemini and OpenAI use 24kHz
    
    _pcmPlayer.onPlaybackStarted = () {
      debugPrint('PCM: Playback started');
      _updateState(ConversationState.speaking);
    };
    
    _pcmPlayer.onPlaybackComplete = () {
      debugPrint('PCM: Playback complete');
      if (_isRunning && _isRealtimeMode()) {
        _updateState(ConversationState.listening);
        // Restart mic streaming after AI finishes speaking (for multi-turn)
        _startMicStreaming();
      }
    };

    _ttsService.onStart = () {
      _isSpeaking = true;
      _updateState(ConversationState.speaking);
    };

    _ttsService.onComplete = () {
      _isSpeaking = false;
      if (_isRunning && !_isProcessing && !_isRealtimeMode()) {
        _startListening();
      }
    };

    _setupRealtimeCallbacks();
  }

  void _setupRealtimeCallbacks() {
    // Gemini Live - native bidirectional audio
    _geminiLiveService.onTranscript = (text) => onUserTranscript?.call(text);
    _geminiLiveService.onResponse = (text) => onAiResponse?.call(text);
    _geminiLiveService.onError = (error) => onError?.call(error);
    _geminiLiveService.onInterrupted = () {
      debugPrint('Gemini Live: User interrupted');
      _pcmPlayer.stop(); // Stop playback on interruption
    };
    // Wire up audio playback for Gemini Live
    _geminiLiveService.onAudio = (audioData) {
      _pcmPlayer.addAudioChunk(audioData);
    };

    // OpenAI Realtime - native bidirectional audio
    _openaiRealtimeService.onTranscript = (text) =>
        onUserTranscript?.call(text);
    _openaiRealtimeService.onResponse = (text) => onAiResponse?.call(text);
    _openaiRealtimeService.onError = (error) => onError?.call(error);
    _openaiRealtimeService.onAiDone = () {
      _pcmPlayer.audioComplete(); // Signal that audio is done
      _updateState(ConversationState.listening);
    };
    // Wire up audio playback for OpenAI Realtime
    _openaiRealtimeService.onAudio = (audioData) {
      _pcmPlayer.addAudioChunk(audioData);
    };
  }

  void configureApiKeys() {
    if (appState.geminiApiKey != null) {
      _geminiFlashService.initialize(appState.geminiApiKey!);
      _geminiLiveService.setApiKey(appState.geminiApiKey!);
    }
    if (appState.openaiApiKey != null) {
      _whisperService.setApiKey(appState.openaiApiKey!);
      _openaiRealtimeService.setApiKey(appState.openaiApiKey!);
      _openaiService.setApiKey(appState.openaiApiKey!);
    }
    if (appState.deepseekApiKey != null) {
      _deepseekService.setApiKey(appState.deepseekApiKey!);
    }
    if (appState.mistralApiKey != null) {
      _mistralService.setApiKey(appState.mistralApiKey!);
    }
  }

  /// Check if using realtime mode (native bidirectional audio)
  bool _isRealtimeMode() {
    return (appState.selectedProvider == AiProvider.gemini &&
            appState.currentMode == AiMode.live) ||
        (appState.selectedProvider == AiProvider.openai &&
            appState.currentMode == AiMode.live);
  }

  /// Start a conversation
  Future<bool> startConversation() async {
    if (_isRunning) return true;

    configureApiKeys();

    if (appState.currentApiKey == null || appState.currentApiKey!.isEmpty) {
      onError?.call('Please set the API key in Settings first.');
      return false;
    }

    await WakelockPlus.enable();
    await BackgroundService.start(); // Acquire native wake lock for screen-off operation
    await audioHandler.startConversation(_getAiName());

    _isRunning = true;
    appState.setConversationActive(true);

    debugPrint(
      'Starting conversation with ${_getAiName()} (realtime: ${_isRealtimeMode()})',
    );

    if (_isRealtimeMode()) {
      // REALTIME MODE: Connect via WebSocket - native bidirectional audio
      return await _startRealtimeSession();
    } else {
      // STANDARD MODE: Use VAD + Whisper STT + AI + TTS
      if (!await _recordingService.requestPermission()) {
        onError?.call('Microphone permission is required.');
        return false;
      }
      _startListening();
      return true;
    }
  }

  /// Start realtime session (Gemini Live or OpenAI Realtime)
  Future<bool> _startRealtimeSession() async {
    _updateState(ConversationState.listening);

    bool connected = false;

    if (appState.selectedProvider == AiProvider.gemini) {
      connected = await _geminiLiveService.connect();
      if (connected) {
        debugPrint('Connected to Gemini Live API - bidirectional audio active');
      }
    } else if (appState.selectedProvider == AiProvider.openai) {
      connected = await _openaiRealtimeService.connect();
      if (connected) {
        debugPrint(
          'Connected to OpenAI Realtime API - bidirectional audio active',
        );
      }
    }

    if (!connected) {
      onError?.call('Failed to connect to realtime API. Check your API key.');
      await stopConversation();
      return false;
    }

    // Start streaming microphone audio to the AI
    await _startMicStreaming();

    return true;
  }

  /// Start streaming microphone to the realtime API
  Future<void> _startMicStreaming() async {
    // Gemini uses 16kHz, OpenAI uses 24kHz
    final sampleRate = appState.selectedProvider == AiProvider.gemini ? 16000 : 24000;
    
    final started = await _recordingService.startStreaming(
      sampleRate: sampleRate,
      onData: (audioData) {
        if (appState.selectedProvider == AiProvider.gemini) {
          _geminiLiveService.sendAudio(audioData);
        } else {
          _openaiRealtimeService.sendAudio(audioData);
        }
      },
    );
    
    if (started) {
      debugPrint('MIC: Streaming to ${appState.selectedProvider} at ${sampleRate}Hz');
    } else {
      onError?.call('Failed to start microphone');
    }
  }


  /// Start listening with VAD (for standard modes only)
  void _startListening() {
    if (!_isRunning || _isProcessing || _isRealtimeMode()) return;

    _updateState(ConversationState.listening);
    _hasDetectedSpeech = false;
    _silenceCount = 0;

    _recordingService.startRecording().then((path) {
      if (path == null) {
        onError?.call('Failed to start recording');
        return;
      }

      debugPrint('Recording started, monitoring for speech...');

      _vadTimer?.cancel();
      _vadTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) {
        _checkVoiceActivity();
      });
    });
  }

  /// Check voice activity based on amplitude
  Future<void> _checkVoiceActivity() async {
    debugPrint('VAD Check: Entered function.');
    if (!_isRunning || _isProcessing) {
      _vadTimer?.cancel();
      return;
    }

    final amplitude = await _recordingService.getAmplitude();
    // debugPrint('VAD Check: Amplitude=${amplitude.toStringAsFixed(3)}');

    if (amplitude > _speechThreshold) {
      _hasDetectedSpeech = true;
      _silenceCount = 0;
    } else if (_hasDetectedSpeech) {
      _silenceCount++;

      if (_silenceCount >= _silenceThreshold) {
        debugPrint('Speech ended, processing...');
        _vadTimer?.cancel();
        await _processRecording();
      }
    }
  }

  /// Process recording (standard mode only)
  Future<void> _processRecording() async {
    if (!_isRunning || _isProcessing) return;

    _isProcessing = true;
    _updateState(ConversationState.processing);

    try {
      final audioPath = await _recordingService.stopRecording();
      if (audioPath == null) {
        _isProcessing = false;
        if (_isRunning) _startListening();
        return;
      }

      if (appState.openaiApiKey == null || appState.openaiApiKey!.isEmpty) {
        onError?.call('OpenAI API key required for speech recognition');
        _isProcessing = false;
        if (_isRunning) _startListening();
        return;
      }

      final transcript = await _whisperService.transcribe(audioPath);
      if (transcript == null || transcript.trim().isEmpty) {
        _isProcessing = false;
        if (_isRunning) _startListening();
        return;
      }

      debugPrint('Transcribed: $transcript');
      onUserTranscript?.call(transcript);

      final lower = transcript.toLowerCase();
      if (lower.contains('stop') || lower.contains('goodbye tangent')) {
        await stopConversation();
        return;
      }

      await _processWithAI(transcript);
    } catch (e) {
      debugPrint('Error: $e');
      onError?.call('Error: $e');
      _isProcessing = false;
      if (_isRunning) _startListening();
    }
  }

  /// Send to AI (standard mode only)
  Future<void> _processWithAI(String message) async {
    String? response;
    final attachment = appState.attachedFile;

    try {
      switch (appState.selectedProvider) {
        case AiProvider.gemini:
          response = await _geminiFlashService.sendMessage(
            message,
            attachment: attachment,
          );
          break;
        case AiProvider.openai:
          response = await _openaiService.sendMessage(
            message,
            attachment: attachment,
          );
          break;
        case AiProvider.deepseek:
          response = await _deepseekService.sendMessage(
            message,
            attachment: attachment,
          );
          break;
        case AiProvider.mistral:
          response = await _mistralService.sendMessage(
            message,
            attachment: attachment,
          );
          break;
      }
    } catch (e) {
      debugPrint('AI error: $e');
      onError?.call('AI error: $e');
    }

    _isProcessing = false;

    if (response != null && response.isNotEmpty) {
      onAiResponse?.call(response);

      if (!appState.textOnlyMode) {
        await _ttsService.speak(response);
      } else {
        if (_isRunning) _startListening();
      }
    } else {
      if (_isRunning) _startListening();
    }
  }

  /// Stop the conversation - idempotent
  Future<void> stopConversation() async {
    if (!_isRunning) return; // Already stopped

    _isRunning = false;
    _isProcessing = false;
    _isSpeaking = false;

    _vadTimer?.cancel();

    await _recordingService.stopRecording();
    await _recordingService.stopStreaming(); // Stop mic streaming for realtime
    await _ttsService.stop();
    await _pcmPlayer.stop(); // Stop any playing audio

    // Only disconnect the service that was actually used
    if (_geminiLiveService.isConnected) {
      _geminiLiveService.disconnect();
    }
    if (_openaiRealtimeService.isConnected) {
      _openaiRealtimeService.disconnect();
    }

    await audioHandler.stopConversation();
    await BackgroundService.stop(); // Release native wake lock
    await WakelockPlus.disable();

    appState.setConversationActive(false);
    _updateState(ConversationState.idle);

    debugPrint('Conversation stopped');
  }

  /// Send text message
  Future<void> sendTextMessage(String message) async {
    if (message.trim().isEmpty || _isProcessing) return;

    if (_isRealtimeMode()) {
      // Send via realtime API
      if (appState.selectedProvider == AiProvider.gemini) {
        _geminiLiveService.sendText(message);
      } else {
        _openaiRealtimeService.sendText(message);
      }
      onUserTranscript?.call(message);
    } else {
      // Standard mode
      _vadTimer?.cancel();
      await _recordingService.stopRecording();

      if (_isSpeaking) {
        _ttsService.stop();
        _isSpeaking = false;
      }

      _isProcessing = true;
      onUserTranscript?.call(message);
      _updateState(ConversationState.processing);

      await _processWithAI(message);
    }
  }

  /// Pause the conversation
  Future<void> pause() async {
    if (!_isRunning) return;
    _vadTimer?.cancel();
    await _recordingService.stopRecording();
    await _ttsService.pause();
    _updateState(ConversationState.sleeping);
  }

  /// Resume the conversation
  Future<void> resume() async {
    if (!_isRunning) return;
    if (_isRealtimeMode()) {
      _updateState(ConversationState.listening);
    } else {
      _startListening();
    }
  }

  void interrupt() {
    if (_isRealtimeMode()) {
      if (appState.selectedProvider == AiProvider.gemini) {
        _geminiLiveService.interrupt();
      } else {
        _openaiRealtimeService.interrupt();
      }
    } else {
      _ttsService.stop();
      _isSpeaking = false;
      if (_isRunning) _startListening();
    }
  }

  String _getAiName() {
    switch (appState.selectedProvider) {
      case AiProvider.gemini:
        return appState.currentMode == AiMode.live
            ? 'Gemini Live'
            : 'Gemini Flash';
      case AiProvider.openai:
        return appState.currentMode == AiMode.live
            ? 'OpenAI Realtime'
            : 'GPT-4o';
      case AiProvider.deepseek:
        return 'Deepseek';
      case AiProvider.mistral:
        return 'Mistral';
    }
  }

  void _updateState(ConversationState state) {
    appState.updateConversationState(state);
    audioHandler.updateConversationState(state);
    onStateChanged?.call(state);
  }

  Future<void> dispose() async {
    await stopConversation();
    await _recordingService.dispose();
    await _ttsService.dispose();
    await _pcmPlayer.dispose();
    _geminiLiveService.dispose();
    _openaiRealtimeService.dispose();
  }
}

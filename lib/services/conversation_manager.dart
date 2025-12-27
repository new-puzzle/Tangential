import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'audio_handler.dart';
import 'background_service.dart';
import 'pcm_audio_player.dart';
import 'native_audio_service.dart';
import 'recording_service.dart';
import 'tts_service.dart';
import 'openai_tts_service.dart';
import 'whisper_service.dart';
import 'gemini_flash_service.dart';
import 'gemini_live_service.dart';
import 'openai_realtime_service.dart';
import 'openai_service.dart';
import 'deepseek_service.dart';
import 'mistral_service.dart';
import '../providers/app_state.dart';

/// Orchestrates the entire conversation flow.
/// - Gemini Live & OpenAI Realtime: Native bidirectional audio via WebSocket
/// - Others (Gemini Flash, GPT-4o, Deepseek, Mistral): VAD + Whisper STT + TTS
class ConversationManager {
  final AppState appState;

  // Core services
  late RecordingService _recordingService;
  late NativeAudioService _nativeAudioService;
  late TtsService _ttsService;
  late OpenaiTtsService _openaiTtsService;
  late WhisperService _whisperService;
  late PcmAudioPlayer _pcmAudioPlayer;

  // AI Services
  late GeminiFlashService _geminiFlashService;
  late GeminiLiveService _geminiLiveService;
  late OpenAiRealtimeService _openaiRealtimeService;
  late OpenAiService _openaiService;
  late DeepseekService _deepseekService;
  late MistralService _mistralService;

  // State
  bool _isRunning = false;
  bool _isProcessing = false;
  bool _isSpeaking = false;
  
  // Health monitoring
  DateTime? _lastAudioReceived;
  DateTime? get lastAudioReceived => _lastAudioReceived;

  // Voice Activity Detection (for standard modes only)
  Timer? _vadTimer;
  Timer? _watchdogTimer; // Safety watchdog for stuck recordings
  bool _hasDetectedSpeech = false;
  int _silenceCount = 0;
  int _speechDuration = 0; // How long user has been speaking (in VAD ticks)
  int _totalRecordingTicks = 0; // Total recording time
  bool _vadCheckInProgress = false;
  int _vadErrorCount = 0;
  double _peakAmplitude = 0.0;
  double _recentAvgAmplitude = 0.0; // Rolling average for noise floor

  // VAD tuning - optimized for walking/noisy environments
  static const int _silenceThreshold =
      12; // ~2.4 seconds of silence - allow natural pauses
  static const double _speechStartThreshold =
      0.08; // Very low - detect any speech
  static const int _maxVadErrors = 3;
  static const int _maxRecordingTicks = 75; // ~15 seconds max recording
  static const int _minSpeechTicks = 3; // Need at least 0.6 seconds of speech
  static const int _watchdogTimeoutSeconds = 60; // Safety timeout for stuck recordings

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
    _nativeAudioService = NativeAudioService();
    _ttsService = TtsService();
    _openaiTtsService = OpenaiTtsService();
    _whisperService = WhisperService();
    _pcmAudioPlayer = PcmAudioPlayer();

    _geminiFlashService = GeminiFlashService();
    _geminiLiveService = GeminiLiveService();
    _openaiRealtimeService = OpenAiRealtimeService();
    _openaiService = OpenAiService();
    _deepseekService = DeepseekService();
    _mistralService = MistralService();

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

    // OpenAI TTS callbacks
    _openaiTtsService.onStart = () {
      _isSpeaking = true;
      _updateState(ConversationState.speaking);
    };

    _openaiTtsService.onComplete = () {
      _isSpeaking = false;
      if (_isRunning && !_isProcessing && !_isRealtimeMode()) {
        _startListening();
      }
    };

    // PCM audio player callbacks for realtime modes
    _pcmAudioPlayer.onPlaybackStarted = () {
      debugPrint('PCM: Playback started - AI is speaking, pausing mic');
      _isSpeaking = true;
      _updateState(ConversationState.speaking);
      // Pause mic streaming while AI speaks (keeps foreground service alive)
      if (_isRealtimeMode()) {
        _nativeAudioService.pauseStreaming();
      }
    };

    _pcmAudioPlayer.onPlaybackComplete = () {
      debugPrint('PCM: Playback complete - ready for next input');
      _isSpeaking = false;
      if (_isRunning && _isRealtimeMode()) {
        _updateState(ConversationState.listening);

        // CRITICAL: Wait for bluetooth to switch modes before resuming mic
        // Bluetooth typically takes 200-400ms to switch from A2DP (music) to SCO (voice)
        // 500ms ensures the switch is complete
        debugPrint('RESUME: Waiting 500ms for bluetooth mode switch...');
        Future.delayed(const Duration(milliseconds: 500), () {
          if (_isRunning && _isRealtimeMode()) {
            debugPrint('RESUME: Resuming mic streaming after delay');
            // Resume instead of restart - keeps foreground service alive
            _nativeAudioService.resumeStreaming();
          }
        });
      }
    };

    _setupRealtimeCallbacks();
  }

  void _setupRealtimeCallbacks() {
    // Gemini Live - native bidirectional audio
    _geminiLiveService.onTranscript = (text) => onUserTranscript?.call(text);
    _geminiLiveService.onResponse = (text) {
      onAiResponse?.call(text);
      _updateState(ConversationState.speaking);
    };
    _geminiLiveService.onAudio = (audioData) {
      _handleReceivedAudio(audioData);
    };
    _geminiLiveService.onError = (error) {
      debugPrint('Gemini Live error callback: $error');
      onError?.call(error);
    };
    _geminiLiveService.onInterrupted = () {
      debugPrint('Gemini Live: User interrupted');
      _pcmAudioPlayer.stop();
      _isSpeaking = false;
      _updateState(ConversationState.listening);
      // Resume mic after interrupt (was paused during AI speech)
      _nativeAudioService.resumeStreaming();
    };
    _geminiLiveService.onTurnComplete = () {
      debugPrint('Gemini Live: Turn complete - audio done');
      _handleAudioComplete();
    };
    _geminiLiveService.onDisconnected = () {
      debugPrint('Gemini Live: Disconnected callback fired');
      _pcmAudioPlayer.stop();
      if (_isRunning) {
        onError?.call('Gemini Live disconnected unexpectedly');
        stopConversation();
      }
    };

    // OpenAI Realtime - native bidirectional audio
    _openaiRealtimeService.onTranscript = (text) =>
        onUserTranscript?.call(text);
    _openaiRealtimeService.onResponse = (text) {
      onAiResponse?.call(text);
      _updateState(ConversationState.speaking);
    };
    _openaiRealtimeService.onAudio = (audioData) {
      _handleReceivedAudio(audioData);
    };
    _openaiRealtimeService.onError = (error) {
      debugPrint('OpenAI Realtime error callback: $error');
      onError?.call(error);
    };
    _openaiRealtimeService.onAiDone = () {
      debugPrint('OpenAI Realtime: AI done - audio complete');
      _handleAudioComplete();
    };
    _openaiRealtimeService.onDisconnected = () {
      debugPrint('OpenAI Realtime: Disconnected callback fired');
      _pcmAudioPlayer.stop();
      if (_isRunning) {
        onError?.call('OpenAI Realtime disconnected unexpectedly');
        stopConversation();
      }
    };
  }

  /// Handle received audio from realtime services - plays via PCM audio player
  void _handleReceivedAudio(Uint8List audioData) {
    // Set sample rate based on provider (Gemini = 24kHz, OpenAI = 24kHz)
    final sampleRate = _getRealtimeSampleRate();
    _pcmAudioPlayer.setSampleRate(sampleRate);

    // Add to player for real-time playback
    _pcmAudioPlayer.addAudioChunk(audioData);

    debugPrint(
      'Playing audio chunk: ${audioData.length} bytes (buffered: ${_pcmAudioPlayer.bufferedBytes})',
    );

    // Update state to show we're receiving/playing audio
    _updateState(ConversationState.speaking);
  }

  /// Signal that AI has finished sending audio
  void _handleAudioComplete() {
    _pcmAudioPlayer.audioComplete();
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
    // Set voices
    _geminiLiveService.setVoice(appState.geminiLiveVoice);
    _openaiRealtimeService.setVoice(appState.openaiRealtimeVoice);

    // Configure OpenAI TTS for standard modes
    if (appState.openaiApiKey != null) {
      _openaiTtsService.setApiKey(appState.openaiApiKey!);
    }
    _openaiTtsService.setVoice(appState.standardModeVoice);
  }

  /// Check if using realtime mode (native bidirectional audio)
  bool _isRealtimeMode() {
    return (appState.selectedProvider == AiProvider.gemini &&
            appState.currentMode == AiMode.live) ||
        (appState.selectedProvider == AiProvider.openai &&
            appState.currentMode == AiMode.live);
  }

  /// Get the sample rate for realtime audio playback
  int _getRealtimeSampleRate() {
    // Gemini Live outputs 24kHz audio, OpenAI Realtime outputs 24kHz
    // Both use 24000 Hz for output audio
    return 24000;
  }

  /// Start a conversation
  Future<bool> startConversation() async {
    if (_isRunning) return true;

    // Ensure API keys are loaded from secure storage
    await appState.loadApiKeys();
    configureApiKeys();

    debugPrint(
      'API Keys: Gemini=${appState.geminiApiKey != null}, OpenAI=${appState.openaiApiKey != null}, '
      'Deepseek=${appState.deepseekApiKey != null}, Mistral=${appState.mistralApiKey != null}',
    );

    if (appState.currentApiKey == null || appState.currentApiKey!.isEmpty) {
      onError?.call(
        'Please set the ${_getProviderName()} API key in Settings.',
      );
      return false;
    }

    // For standard modes, we need OpenAI key for Whisper transcription
    if (!_isRealtimeMode()) {
      if (appState.openaiApiKey == null || appState.openaiApiKey!.isEmpty) {
        onError?.call(
          'Standard modes require OpenAI API key for speech recognition. Please set it in Settings.',
        );
        return false;
      }
    }

    await WakelockPlus.enable();
    await BackgroundService.start();
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

    // Request mic permission first
    if (!await _recordingService.requestPermission()) {
      onError?.call('Microphone permission is required.');
      return false;
    }

    bool connected = false;
    String errorDetail = '';

    if (appState.selectedProvider == AiProvider.gemini) {
      debugPrint('Attempting Gemini Live connection...');
      connected = await _geminiLiveService.connect();
      if (connected) {
        debugPrint('Connected to Gemini Live API - bidirectional audio active');
        // Start streaming audio to Gemini Live
        await _startAudioStreaming();
      } else {
        errorDetail =
            'Gemini Live connection failed. Check your API key and try again.';
      }
    } else if (appState.selectedProvider == AiProvider.openai) {
      debugPrint('Attempting OpenAI Realtime connection...');
      connected = await _openaiRealtimeService.connect();
      if (connected) {
        debugPrint(
          'Connected to OpenAI Realtime API - bidirectional audio active',
        );
        // Start streaming audio to OpenAI Realtime
        await _startAudioStreaming();
      } else {
        errorDetail =
            'OpenAI Realtime connection failed. Check your API key and try again.';
      }
    }

    if (!connected) {
      onError?.call(
        errorDetail.isNotEmpty
            ? errorDetail
            : 'Failed to connect to realtime API.',
      );
      await stopConversation();
      return false;
    }

    return true;
  }

  /// Start streaming microphone audio to realtime service
  Future<void> _startAudioStreaming() async {
    debugPrint('STREAM: _startAudioStreaming called');
    final isGemini = appState.selectedProvider == AiProvider.gemini;
    // Gemini Live: 16kHz, OpenAI Realtime: 24kHz
    final sampleRate = isGemini ? 16000 : 24000;
    debugPrint(
      'STREAM: Provider=${isGemini ? "Gemini" : "OpenAI"}, sampleRate=$sampleRate',
    );

    // Send audio to the appropriate realtime service
    Future<void> onChunk(Uint8List audioData) async {
      // Update heartbeat timestamp
      _lastAudioReceived = DateTime.now();
      
      if (isGemini) {
        _geminiLiveService.sendAudio(audioData);
      } else {
        _openaiRealtimeService.sendAudio(audioData);
      }
    }

    // Always use native audio foreground service for realtime modes
    final success = await _nativeAudioService.startStreaming(
      sampleRate: sampleRate,
      onData: onChunk,
    );

    if (!success) {
      debugPrint('STREAM ERROR: Failed to start audio streaming');
      onError?.call('Failed to start microphone streaming');
    } else {
      debugPrint(
        'Audio streaming started (${sampleRate}Hz) via foreground service - sending to ${isGemini ? "Gemini Live" : "OpenAI Realtime"}',
      );
    }
  }

  /// Stop audio streaming for realtime mode
  Future<void> _stopAudioStreaming() async {
    await _nativeAudioService.stopStreaming();
  }

  /// Start listening with VAD (for standard modes only)
  /// Uses NativeAudioService (foreground service) to prevent Android throttling
  void _startListening() {
    if (!_isRunning || _isProcessing || _isRealtimeMode()) return;

    _updateState(ConversationState.listening);

    // Reset all VAD state
    _hasDetectedSpeech = false;
    _silenceCount = 0;
    _speechDuration = 0;
    _totalRecordingTicks = 0;
    _vadCheckInProgress = false;
    _vadErrorCount = 0;
    _peakAmplitude = 0.0;
    _recentAvgAmplitude = 0.0;

    // Use NativeAudioService with buffered mode for standard modes
    // This uses Android foreground service, which prevents throttling when screen is off
    _nativeAudioService.startBufferedStreaming(sampleRate: 16000).then((success) {
      if (!success) {
        onError?.call('Failed to start audio recording');
        return;
      }

      debugPrint(
        'NativeAudio: Buffered streaming started - VAD active (max ${_maxRecordingTicks * 200}ms)',
      );

      _vadTimer?.cancel();
      _vadTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) {
        if (_vadCheckInProgress) return;
        _checkVoiceActivity();
      });

      // Start watchdog timer to prevent stuck recordings
      _startWatchdog();
    });
  }

  /// Start watchdog timer - force-recovers from stuck states
  void _startWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer(Duration(seconds: _watchdogTimeoutSeconds), () {
      if (!_isRunning) return;

      debugPrint('WATCHDOG: Timeout triggered! Force recovering...');

      // Force cancel VAD timer
      _vadTimer?.cancel();

      // Clear any stuck state
      _vadCheckInProgress = false;
      _isProcessing = false;

      // Stop and restart audio
      _nativeAudioService.stopStreaming().then((_) {
        if (_isRunning && !_isRealtimeMode()) {
          debugPrint('WATCHDOG: Restarting listening...');
          _startListening();
        }
      });
    });
  }

  /// Cancel watchdog timer
  void _cancelWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
  }

  /// Check voice activity based on amplitude (optimized for noisy environments)
  /// Now uses NativeAudioService amplitude which is calculated from PCM chunks
  Future<void> _checkVoiceActivity() async {
    _vadCheckInProgress = true;

    try {
      if (!_isRunning || _isProcessing) {
        _vadTimer?.cancel();
        return;
      }

      _totalRecordingTicks++;

      // SAFETY: Max recording time reached - process whatever we have
      if (_totalRecordingTicks >= _maxRecordingTicks) {
        debugPrint('VAD: Max recording time reached, processing...');
        _vadTimer?.cancel();
        await _processRecording();
        return;
      }

      // Get amplitude from NativeAudioService (synchronous, from latest PCM chunk)
      final amplitude = _nativeAudioService.getAmplitude();

      // Check if streaming stopped unexpectedly
      if (!_nativeAudioService.isStreaming) {
        _vadErrorCount++;
        if (_vadErrorCount >= _maxVadErrors) {
          debugPrint('VAD: Audio streaming stopped unexpectedly, processing...');
          _vadTimer?.cancel();
          if (_hasDetectedSpeech) {
            await _processRecording();
          } else {
            _isProcessing = false;
            if (_isRunning) _startListening();
          }
        }
        return;
      }
      _vadErrorCount = 0;

      // Update rolling average (noise floor estimation)
      _recentAvgAmplitude = (_recentAvgAmplitude * 0.8) + (amplitude * 0.2);

      // Track peak amplitude during speech
      if (_hasDetectedSpeech && amplitude > _peakAmplitude) {
        _peakAmplitude = amplitude;
      }

      // Dynamic threshold: speech is anything significantly above noise floor
      final speechThreshold = (_recentAvgAmplitude * 1.5).clamp(
        _speechStartThreshold,
        0.5,
      );

      // Silence threshold: dropped to near noise floor level
      // Ensure min <= max for clamp to work correctly
      final minSilence = _recentAvgAmplitude * 1.1;
      final maxSilence = _peakAmplitude * 0.5;
      final silenceThreshold = _hasDetectedSpeech
          ? (_peakAmplitude * 0.3).clamp(
              minSilence < maxSilence ? minSilence : maxSilence,
              minSilence < maxSilence ? maxSilence : minSilence,
            )
          : _speechStartThreshold;

      if (amplitude > speechThreshold) {
        // Speech detected
        if (!_hasDetectedSpeech) {
          debugPrint(
            'VAD: Speech started! (amp=${amplitude.toStringAsFixed(3)}, threshold=${speechThreshold.toStringAsFixed(3)})',
          );
          _peakAmplitude = amplitude;
        }
        _hasDetectedSpeech = true;
        _speechDuration++;
        _silenceCount = 0;
      } else if (_hasDetectedSpeech) {
        // Was speaking, now quieter - is it silence?
        if (amplitude < silenceThreshold) {
          _silenceCount++;

          // Only process if we have enough speech AND enough silence
          if (_speechDuration >= _minSpeechTicks &&
              _silenceCount >= _silenceThreshold) {
            debugPrint(
              'VAD: Speech ended after ${_speechDuration * 200}ms, processing...',
            );
            _vadTimer?.cancel();
            await _processRecording();
            return;
          }
        } else {
          // Amplitude between speech and silence thresholds - keep listening
          if (_silenceCount > 0) _silenceCount--;
        }
      }

      // Debug every 5 ticks (1 second)
      if (_totalRecordingTicks % 5 == 0) {
        debugPrint(
          'VAD: tick=$_totalRecordingTicks amp=${amplitude.toStringAsFixed(3)} noise=${_recentAvgAmplitude.toStringAsFixed(3)} speech=$_hasDetectedSpeech dur=$_speechDuration silence=$_silenceCount',
        );
      }
    } finally {
      _vadCheckInProgress = false;
    }
  }

  /// Process recording (standard mode only)
  /// Uses NativeAudioService buffered mode - pauses streaming, saves buffer to WAV, transcribes
  Future<void> _processRecording() async {
    if (!_isRunning || _isProcessing) return;

    _isProcessing = true;
    _updateState(ConversationState.processing);

    // Cancel watchdog while processing (we're no longer listening)
    _cancelWatchdog();

    try {
      // Pause streaming (keeps foreground service alive for next turn)
      await _nativeAudioService.pauseStreaming();

      // Save buffered audio to WAV file
      final audioPath = await _nativeAudioService.saveBufferToFile();
      if (audioPath == null) {
        debugPrint('No audio captured in buffer');
        _isProcessing = false;
        // Resume streaming for next turn
        await _nativeAudioService.resumeStreaming();
        if (_isRunning) _startListening();
        return;
      }

      if (appState.openaiApiKey == null || appState.openaiApiKey!.isEmpty) {
        onError?.call('OpenAI API key required for speech recognition');
        _isProcessing = false;
        await _nativeAudioService.resumeStreaming();
        if (_isRunning) _startListening();
        return;
      }

      debugPrint('Sending ${_nativeAudioService.bufferedDurationMs}ms audio to Whisper...');
      final transcript = await _whisperService.transcribe(audioPath);
      if (transcript == null || transcript.trim().isEmpty) {
        debugPrint(
          'Transcription returned empty - no speech detected or API error',
        );
        // Don't show error for empty speech, just restart listening
        _isProcessing = false;
        await _nativeAudioService.resumeStreaming();
        if (_isRunning) _startListening();
        return;
      }

      debugPrint('Transcribed: "$transcript"');
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
      await _nativeAudioService.resumeStreaming();
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
        // Use OpenAI TTS if enabled, otherwise device TTS
        if (appState.useOpenaiTts && appState.openaiApiKey != null) {
          await _openaiTtsService.speak(response);
        } else {
          await _ttsService.speak(response);
        }
      } else {
        if (_isRunning) _startListening();
      }
    } else {
      if (_isRunning) _startListening();
    }
  }

  /// Stop the conversation - idempotent
  /// Forces all audio/AI to stop and cleans up resources
  Future<void> stopConversation() async {
    if (!_isRunning) return; // Already stopped

    _isRunning = false;
    _isProcessing = false;
    _isSpeaking = false;

    // Cancel all timers
    _vadTimer?.cancel();
    _cancelWatchdog();

    // Clear audio buffer
    _nativeAudioService.clearBuffer();

    // Stop audio streaming (both realtime and standard modes use this now)
    await _stopAudioStreaming();
    await _ttsService.stop();
    await _openaiTtsService.stop();
    await _pcmAudioPlayer.stop();

    // Only disconnect the service that was actually used
    if (_geminiLiveService.isConnected) {
      _geminiLiveService.disconnect();
    }
    if (_openaiRealtimeService.isConnected) {
      _openaiRealtimeService.disconnect();
    }

    await audioHandler.stopConversation();
    await WakelockPlus.disable();
    await BackgroundService.stop();

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
      // Standard mode - stop VAD and audio capture
      _vadTimer?.cancel();
      // Clear buffer and pause (don't stop - keeps foreground service for next turn)
      _nativeAudioService.clearBuffer();
      await _nativeAudioService.pauseStreaming();

      if (_isSpeaking) {
        _ttsService.stop();
        _openaiTtsService.stop();
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
    // Pause audio capture (keeps foreground service alive)
    _nativeAudioService.clearBuffer();
    await _nativeAudioService.pauseStreaming();
    await _ttsService.stop();
    await _openaiTtsService.stop();
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
      _openaiTtsService.stop();
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

  String _getProviderName() {
    switch (appState.selectedProvider) {
      case AiProvider.gemini:
        return 'Gemini';
      case AiProvider.openai:
        return 'OpenAI';
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
    _pcmAudioPlayer.dispose();
    _geminiLiveService.dispose();
    _openaiRealtimeService.dispose();
  }
}

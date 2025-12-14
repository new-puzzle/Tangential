import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../services/audio_handler.dart';

/// Available AI providers
enum AiProvider { gemini, openai, deepseek, mistral }

/// AI mode for providers that support multiple modes
enum AiMode {
  live, // Real-time bidirectional (Gemini Live, OpenAI Realtime)
  standard, // STT -> API -> TTS flow with file upload support
}

/// Central application state using ChangeNotifier
class AppState extends ChangeNotifier {
  // Storage for API keys
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  // Current AI selection
  AiProvider _selectedProvider = AiProvider.gemini;
  final Map<AiProvider, AiMode> _providerModes = {
    AiProvider.gemini: AiMode.live,
    AiProvider.openai: AiMode.live,
    AiProvider.deepseek: AiMode.standard,
    AiProvider.mistral: AiMode.standard,
  };

  // Conversation state
  ConversationState _conversationState = ConversationState.idle;
  bool _isConversationActive = false;

  // Transcription
  String _userTranscript = '';
  String _aiTranscript = '';
  final List<TranscriptEntry> _transcriptHistory = [];

  // File attachment
  File? _attachedFile;
  String? _attachedFileName;

  // API Keys (cached from secure storage)
  String? _geminiApiKey;
  String? _openaiApiKey;
  String? _deepseekApiKey;
  String? _mistralApiKey;

  // Settings
  int _sleepTimeoutSeconds = 120; // 2 minutes
  bool _wakeWordEnabled = true;
  int _audioRetentionDays = 30;
  bool _textOnlyMode = false; // Skip TTS, show text only

  // Getters
  AiProvider get selectedProvider => _selectedProvider;
  AiMode get currentMode => _providerModes[_selectedProvider]!;
  ConversationState get conversationState => _conversationState;
  bool get isConversationActive => _isConversationActive;
  String get userTranscript => _userTranscript;
  String get aiTranscript => _aiTranscript;
  List<TranscriptEntry> get transcriptHistory =>
      List.unmodifiable(_transcriptHistory);
  File? get attachedFile => _attachedFile;
  String? get attachedFileName => _attachedFileName;
  int get sleepTimeoutSeconds => _sleepTimeoutSeconds;
  bool get wakeWordEnabled => _wakeWordEnabled;
  int get audioRetentionDays => _audioRetentionDays;
  bool get textOnlyMode => _textOnlyMode;

  // API Key getters
  String? get geminiApiKey => _geminiApiKey;
  String? get openaiApiKey => _openaiApiKey;
  String? get deepseekApiKey => _deepseekApiKey;
  String? get mistralApiKey => _mistralApiKey;

  /// Get API key for the selected provider
  String? get currentApiKey {
    switch (_selectedProvider) {
      case AiProvider.gemini:
        return _geminiApiKey;
      case AiProvider.openai:
        return _openaiApiKey;
      case AiProvider.deepseek:
        return _deepseekApiKey;
      case AiProvider.mistral:
        return _mistralApiKey;
    }
  }

  /// Check if the current provider supports live/realtime mode
  bool get currentProviderSupportsLive {
    return _selectedProvider == AiProvider.gemini ||
        _selectedProvider == AiProvider.openai;
  }

  // Setters
  void selectProvider(AiProvider provider) {
    _selectedProvider = provider;
    notifyListeners();
  }

  void setMode(AiProvider provider, AiMode mode) {
    _providerModes[provider] = mode;
    notifyListeners();
  }

  void updateConversationState(ConversationState state) {
    _conversationState = state;
    notifyListeners();
  }

  void setConversationActive(bool active) {
    _isConversationActive = active;
    if (!active) {
      _conversationState = ConversationState.idle;
    }
    notifyListeners();
  }

  void updateUserTranscript(String text) {
    _userTranscript = text;
    notifyListeners();
  }

  void updateAiTranscript(String text) {
    _aiTranscript = text;
    notifyListeners();
  }

  void addToHistory(TranscriptEntry entry) {
    _transcriptHistory.add(entry);
    notifyListeners();
  }

  void clearCurrentTranscripts() {
    _userTranscript = '';
    _aiTranscript = '';
    notifyListeners();
  }

  // File attachment
  void attachFile(File file, String fileName) {
    _attachedFile = file;
    _attachedFileName = fileName;
    notifyListeners();
  }

  void clearAttachment() {
    _attachedFile = null;
    _attachedFileName = null;
    notifyListeners();
  }

  // Settings
  void setSleepTimeout(int seconds) {
    _sleepTimeoutSeconds = seconds;
    notifyListeners();
  }

  void setWakeWordEnabled(bool enabled) {
    _wakeWordEnabled = enabled;
    notifyListeners();
  }

  void setAudioRetentionDays(int days) {
    _audioRetentionDays = days;
    notifyListeners();
  }

  void setTextOnlyMode(bool enabled) {
    _textOnlyMode = enabled;
    notifyListeners();
  }

  // API Key management
  Future<void> loadApiKeys() async {
    _geminiApiKey = await _secureStorage.read(key: 'gemini_api_key');
    _openaiApiKey = await _secureStorage.read(key: 'openai_api_key');
    _deepseekApiKey = await _secureStorage.read(key: 'deepseek_api_key');
    _mistralApiKey = await _secureStorage.read(key: 'mistral_api_key');
    notifyListeners();
  }

  Future<void> setGeminiApiKey(String key) async {
    await _secureStorage.write(key: 'gemini_api_key', value: key);
    _geminiApiKey = key;
    notifyListeners();
  }

  Future<void> setOpenaiApiKey(String key) async {
    await _secureStorage.write(key: 'openai_api_key', value: key);
    _openaiApiKey = key;
    notifyListeners();
  }

  Future<void> setDeepseekApiKey(String key) async {
    await _secureStorage.write(key: 'deepseek_api_key', value: key);
    _deepseekApiKey = key;
    notifyListeners();
  }

  Future<void> setMistralApiKey(String key) async {
    await _secureStorage.write(key: 'mistral_api_key', value: key);
    _mistralApiKey = key;
    notifyListeners();
  }
}

/// A single entry in the transcript history
class TranscriptEntry {
  final String speaker; // 'user' or 'ai'
  final String text;
  final DateTime timestamp;
  final AiProvider? provider;

  TranscriptEntry({
    required this.speaker,
    required this.text,
    required this.timestamp,
    this.provider,
  });
}

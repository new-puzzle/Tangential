import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../providers/app_state.dart';
import '../services/audio_handler.dart';
import '../services/conversation_manager.dart';
import '../widgets/ai_button.dart';
import '../widgets/transcription_display.dart';
import '../widgets/text_input.dart';
import '../widgets/file_attachment.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  late ConversationManager _conversationManager;
  late AnimationController _pulseController;
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  final List<TranscriptEntry> _transcriptEntries = [];
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInitialized) {
      final appState = context.read<AppState>();
      _conversationManager = ConversationManager(appState: appState);
      _setupCallbacks();
      _isInitialized = true;
    }
  }

  void _setupCallbacks() {
    _conversationManager.onUserTranscript = (text) {
      setState(() {
        _transcriptEntries.add(
          TranscriptEntry(
            speaker: 'user',
            text: text,
            timestamp: DateTime.now(),
          ),
        );
      });
      _scrollToBottom();
    };

    _conversationManager.onAiResponse = (text) {
      setState(() {
        _transcriptEntries.add(
          TranscriptEntry(
            speaker: 'ai',
            text: text,
            timestamp: DateTime.now(),
            provider: context.read<AppState>().selectedProvider,
          ),
        );
      });
      _scrollToBottom();
    };

    _conversationManager.onError = (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error),
          backgroundColor: Colors.red.shade800,
          action: SnackBarAction(
            label: 'Settings',
            textColor: Colors.white,
            onPressed: () => Navigator.pushNamed(context, '/settings'),
          ),
        ),
      );
    };

    // Set up audio handler callbacks
    audioHandler.onStopRequested = () {
      _stopConversation();
    };
    audioHandler.onPauseRequested = () {
      _conversationManager.pause();
    };
    audioHandler.onResumeRequested = () {
      _conversationManager.resume();
    };
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _requestPermissions() async {
    await Permission.microphone.request();
    await Permission.notification.request();
  }

  Future<void> _startConversation() async {
    await _requestPermissions();
    final success = await _conversationManager.startConversation();
    if (!success && mounted) {
      // Error already shown via callback
    }
  }

  Future<void> _stopConversation() async {
    await _conversationManager.stopConversation();
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        'pdf',
        'png',
        'jpg',
        'jpeg',
        'gif',
        'webp',
        'txt',
        'md',
      ],
    );

    if (result != null && result.files.single.path != null) {
      final file = File(result.files.single.path!);
      final fileName = result.files.single.name;
      context.read<AppState>().attachFile(file, fileName);
    }
  }

  void _sendTextMessage() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    _textController.clear();
    _conversationManager.sendTextMessage(text);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _textController.dispose();
    _scrollController.dispose();
    _conversationManager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tangential'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'History',
            onPressed: () => Navigator.pushNamed(context, '/history'),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () => Navigator.pushNamed(context, '/settings'),
          ),
        ],
      ),
      body: Consumer<AppState>(
        builder: (context, appState, child) {
          return Column(
            children: [
              // AI Provider Buttons
              _buildAiProviderSection(appState),

              const SizedBox(height: 8),

              // File Attachment
              FileAttachmentWidget(
                fileName: appState.attachedFileName,
                onAttach: _pickFile,
                onClear: () => appState.clearAttachment(),
              ),

              const SizedBox(height: 8),

              // Transcription Display
              Expanded(
                child: TranscriptionDisplay(
                  entries: _transcriptEntries,
                  scrollController: _scrollController,
                  conversationState: appState.conversationState,
                ),
              ),

              // Start/Stop Button
              _buildControlButton(appState),

              const SizedBox(height: 8),

              // Text Input
              TextInputWidget(
                controller: _textController,
                onSend: _sendTextMessage,
                enabled: appState.isConversationActive,
              ),

              const SizedBox(height: 8),
            ],
          );
        },
      ),
    );
  }

  Widget _buildAiProviderSection(AppState appState) {
    // This horizontal scroll view uses less vertical space and prevents overflow.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        children: <Widget>[
          AiButton(
            provider: AiProvider.gemini,
            isSelected: appState.selectedProvider == AiProvider.gemini,
            onTap: () => appState.selectProvider(AiProvider.gemini),
            mode: appState.currentMode,
            onModeChanged: (mode) =>
                appState.setMode(AiProvider.gemini, mode),
            showModeToggle: true,
            color: const Color(0xFF4285F4), // Google blue
          ),
          const SizedBox(width: 12),
          AiButton(
            provider: AiProvider.openai,
            isSelected: appState.selectedProvider == AiProvider.openai,
            onTap: () => appState.selectProvider(AiProvider.openai),
            mode: appState.currentMode,
            onModeChanged: (mode) =>
                appState.setMode(AiProvider.openai, mode),
            showModeToggle: true,
            color: const Color(0xFF10A37F), // OpenAI green
          ),
          const SizedBox(width: 12),
          AiButton(
            provider: AiProvider.deepseek,
            isSelected: appState.selectedProvider == AiProvider.deepseek,
            onTap: () => appState.selectProvider(AiProvider.deepseek),
            color: const Color(0xFF6366F1), // Indigo
          ),
          const SizedBox(width: 12),
          AiButton(
            provider: AiProvider.mistral,
            isSelected: appState.selectedProvider == AiProvider.mistral,
            onTap: () => appState.selectProvider(AiProvider.mistral),
            color: const Color(0xFFFF7000), // Mistral orange
          ),
        ],
      ),
    );
  }

  Widget _buildControlButton(AppState appState) {
    final isActive = appState.isConversationActive;
    final state = appState.conversationState;

    String statusText;
    IconData icon;
    Color color;

    if (!isActive) {
      statusText = 'Start Conversation';
      icon = Icons.mic;
      color = Theme.of(context).colorScheme.primary;
    } else {
      switch (state) {
        case ConversationState.listening:
          statusText = 'Listening...';
          icon = Icons.hearing;
          color = Colors.green;
          break;
        case ConversationState.processing:
          statusText = 'Thinking...';
          icon = Icons.psychology;
          color = Colors.amber;
          break;
        case ConversationState.speaking:
          statusText = 'Speaking...';
          icon = Icons.volume_up;
          color = Colors.blue;
          break;
        case ConversationState.sleeping:
          statusText = 'Sleeping - Tap to wake';
          icon = Icons.bedtime;
          color = Colors.purple;
          break;
        case ConversationState.idle:
          statusText = 'Start Conversation';
          icon = Icons.mic;
          color = Theme.of(context).colorScheme.primary;
          break;
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          final scale = isActive && state == ConversationState.listening
              ? 1.0 + (_pulseController.value * 0.05)
              : 1.0;

          return Transform.scale(
            scale: scale,
            child: SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: isActive ? _stopConversation : _startConversation,
                icon: Icon(isActive ? Icons.stop : icon),
                label: Text(isActive ? 'Stop' : statusText),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isActive ? Colors.red.shade700 : color,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

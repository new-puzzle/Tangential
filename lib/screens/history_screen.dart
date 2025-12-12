import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../providers/app_state.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Placeholder data - would come from database
  final List<ConversationHistory> _geminiHistory = [];
  final List<ConversationHistory> _openaiHistory = [];
  final List<ConversationHistory> _deepseekHistory = [];
  final List<ConversationHistory> _mistralHistory = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadHistory();
  }

  void _loadHistory() {
    // TODO: Load from database
    // For now, show empty state or sample data
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Gemini'),
            Tab(text: 'OpenAI'),
            Tab(text: 'Deepseek'),
            Tab(text: 'Mistral'),
          ],
          labelColor: Theme.of(context).colorScheme.secondary,
          unselectedLabelColor: Colors.white54,
          indicatorColor: Theme.of(context).colorScheme.secondary,
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildHistoryList(_geminiHistory, AiProvider.gemini),
          _buildHistoryList(_openaiHistory, AiProvider.openai),
          _buildHistoryList(_deepseekHistory, AiProvider.deepseek),
          _buildHistoryList(_mistralHistory, AiProvider.mistral),
        ],
      ),
    );
  }

  Widget _buildHistoryList(
    List<ConversationHistory> history,
    AiProvider provider,
  ) {
    if (history.isEmpty) {
      return _buildEmptyState(provider);
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: history.length,
      itemBuilder: (context, index) {
        final conversation = history[index];
        return _buildHistoryCard(conversation, provider);
      },
    );
  }

  Widget _buildEmptyState(AiProvider provider) {
    Color color;
    String name;

    switch (provider) {
      case AiProvider.gemini:
        color = const Color(0xFF4285F4);
        name = 'Gemini';
        break;
      case AiProvider.openai:
        color = const Color(0xFF10A37F);
        name = 'OpenAI';
        break;
      case AiProvider.deepseek:
        color = const Color(0xFF6366F1);
        name = 'Deepseek';
        break;
      case AiProvider.mistral:
        color = const Color(0xFFFF7000);
        name = 'Mistral';
        break;
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history, size: 64, color: color.withOpacity(0.3)),
          const SizedBox(height: 16),
          Text(
            'No $name conversations yet',
            style: TextStyle(color: Colors.white54, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            'Start a conversation to see it here',
            style: TextStyle(color: Colors.white38, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryCard(
    ConversationHistory conversation,
    AiProvider provider,
  ) {
    final dateFormat = DateFormat.yMMMd();
    final timeFormat = DateFormat.Hm();

    Color color;
    switch (provider) {
      case AiProvider.gemini:
        color = const Color(0xFF4285F4);
        break;
      case AiProvider.openai:
        color = const Color(0xFF10A37F);
        break;
      case AiProvider.deepseek:
        color = const Color(0xFF6366F1);
        break;
      case AiProvider.mistral:
        color = const Color(0xFFFF7000);
        break;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _viewConversation(conversation),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 4,
                    height: 40,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          dateFormat.format(conversation.startTime),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${timeFormat.format(conversation.startTime)} - ${conversation.messageCount} messages',
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.more_vert, color: Colors.white54),
                    onPressed: () => _showOptions(conversation),
                  ),
                ],
              ),
              if (conversation.preview != null) ...[
                const SizedBox(height: 12),
                Text(
                  conversation.preview!,
                  style: const TextStyle(color: Colors.white70),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _viewConversation(ConversationHistory conversation) {
    // TODO: Navigate to conversation detail view
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Conversation viewer coming soon')),
    );
  }

  void _showOptions(ConversationHistory conversation) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.visibility),
              title: const Text('View Conversation'),
              onTap: () {
                Navigator.pop(context);
                _viewConversation(conversation);
              },
            ),
            if (conversation.hasAudio)
              ListTile(
                leading: const Icon(Icons.play_arrow),
                title: const Text('Play Audio'),
                onTap: () {
                  Navigator.pop(context);
                  // TODO: Play audio
                },
              ),
            ListTile(
              leading: const Icon(Icons.share),
              title: const Text('Export'),
              onTap: () {
                Navigator.pop(context);
                // TODO: Export conversation
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Delete', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _confirmDelete(conversation);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(ConversationHistory conversation) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Conversation?'),
        content: const Text(
          'This will permanently delete this conversation and any associated audio recordings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // TODO: Delete from database
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Conversation deleted')),
              );
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

/// Model for conversation history display
class ConversationHistory {
  final String id;
  final DateTime startTime;
  final DateTime endTime;
  final int messageCount;
  final String? preview;
  final bool hasAudio;
  final AiProvider provider;

  ConversationHistory({
    required this.id,
    required this.startTime,
    required this.endTime,
    required this.messageCount,
    this.preview,
    this.hasAudio = false,
    required this.provider,
  });
}

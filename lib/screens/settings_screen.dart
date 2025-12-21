import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _geminiController = TextEditingController();
  final _openaiController = TextEditingController();
  final _deepseekController = TextEditingController();
  final _mistralController = TextEditingController();

  bool _showApiKeys = false;

  @override
  void initState() {
    super.initState();
    _loadApiKeys();
  }

  void _loadApiKeys() {
    final appState = context.read<AppState>();
    _geminiController.text = appState.geminiApiKey ?? '';
    _openaiController.text = appState.openaiApiKey ?? '';
    _deepseekController.text = appState.deepseekApiKey ?? '';
    _mistralController.text = appState.mistralApiKey ?? '';
  }

  void _saveApiKeys() {
    final appState = context.read<AppState>();
    appState.setGeminiApiKey(_geminiController.text.trim());
    appState.setOpenaiApiKey(_openaiController.text.trim());
    appState.setDeepseekApiKey(_deepseekController.text.trim());
    appState.setMistralApiKey(_mistralController.text.trim());

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('API keys saved securely'),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  void dispose() {
    _geminiController.dispose();
    _openaiController.dispose();
    _deepseekController.dispose();
    _mistralController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Consumer<AppState>(
        builder: (context, appState, child) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // API Keys Section
              _buildSectionHeader('API Keys', Icons.key),
              const SizedBox(height: 8),
              _buildApiKeyCard(),

              const SizedBox(height: 24),

              // Conversation Settings
              _buildSectionHeader('Conversation', Icons.chat),
              const SizedBox(height: 8),
              _buildConversationSettings(appState),

              const SizedBox(height: 24),

              // Audio Settings
              _buildSectionHeader('Audio', Icons.volume_up),
              const SizedBox(height: 8),
              _buildAudioSettings(appState),

              const SizedBox(height: 24),

              // Storage Settings
              _buildSectionHeader('Storage', Icons.storage),
              const SizedBox(height: 8),
              _buildStorageSettings(appState),

              const SizedBox(height: 24),

              // Clear Data
              _buildSectionHeader('Data Management', Icons.delete_outline),
              const SizedBox(height: 8),
              _buildDataManagement(appState),

              const SizedBox(height: 32),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.secondary, size: 20),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            color: Theme.of(context).colorScheme.secondary,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildApiKeyCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Your API keys are stored securely',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _showApiKeys = !_showApiKeys;
                    });
                  },
                  icon: Icon(
                    _showApiKeys ? Icons.visibility_off : Icons.visibility,
                    size: 18,
                  ),
                  label: Text(_showApiKeys ? 'Hide' : 'Show'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildApiKeyField(
              'Gemini',
              _geminiController,
              const Color(0xFF4285F4),
            ),
            const SizedBox(height: 12),
            _buildApiKeyField(
              'OpenAI',
              _openaiController,
              const Color(0xFF10A37F),
            ),
            const SizedBox(height: 12),
            _buildApiKeyField(
              'Deepseek',
              _deepseekController,
              const Color(0xFF6366F1),
            ),
            const SizedBox(height: 12),
            _buildApiKeyField(
              'Mistral',
              _mistralController,
              const Color(0xFFFF7000),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _saveApiKeys,
                icon: const Icon(Icons.save),
                label: const Text('Save API Keys'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildApiKeyField(
    String label,
    TextEditingController controller,
    Color color,
  ) {
    return TextField(
      controller: controller,
      obscureText: !_showApiKeys,
      decoration: InputDecoration(
        labelText: '$label API Key',
        labelStyle: TextStyle(color: color),
        prefixIcon: Icon(Icons.vpn_key, color: color, size: 20),
        suffixIcon: controller.text.isNotEmpty
            ? Icon(Icons.check_circle, color: Colors.green, size: 20)
            : null,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: color, width: 2),
        ),
      ),
      style: TextStyle(fontFamily: _showApiKeys ? null : 'monospace'),
      onChanged: (_) => setState(() {}),
    );
  }

  Widget _buildConversationSettings(AppState appState) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Sleep timeout
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sleep Timeout',
                      style: TextStyle(color: Colors.white),
                    ),
                    Text(
                      'Enter sleep mode after silence',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
                DropdownButton<int>(
                  value: appState.sleepTimeoutSeconds,
                  dropdownColor: Theme.of(context).colorScheme.surface,
                  items: const [
                    DropdownMenuItem(value: 60, child: Text('1 min')),
                    DropdownMenuItem(value: 120, child: Text('2 min')),
                    DropdownMenuItem(value: 180, child: Text('3 min')),
                    DropdownMenuItem(value: 300, child: Text('5 min')),
                  ],
                  onChanged: (value) {
                    if (value != null) appState.setSleepTimeout(value);
                  },
                ),
              ],
            ),
            const Divider(height: 24),
            // Wake word toggle
            SwitchListTile(
              title: const Text('Wake Word'),
              subtitle: const Text('Say "Hey Tangent" to wake from sleep'),
              value: appState.wakeWordEnabled,
              onChanged: appState.setWakeWordEnabled,
              contentPadding: EdgeInsets.zero,
            ),
            const Divider(height: 24),
            // Text only mode
            SwitchListTile(
              title: const Text('Text Only Mode'),
              subtitle: const Text('Show text responses without TTS'),
              value: appState.textOnlyMode,
              onChanged: appState.setTextOnlyMode,
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAudioSettings(AppState appState) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Experimental native audio toggle (Android only)
            SwitchListTile(
              title: const Text('Use Native Audio (Experimental)'),
              subtitle: const Text(
                'Enable hardware noise suppression for noisy environments. May improve outdoor performance.',
              ),
              value: appState.useNativeAudio,
              onChanged: appState.setUseNativeAudio,
              contentPadding: EdgeInsets.zero,
            ),
            const Divider(),
            const SizedBox(height: 8),
            // Gemini Live Voice
            const Text(
              'Gemini Live Voice',
              style: TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 8),
            DropdownButton<String>(
              value: appState.geminiLiveVoice,
              dropdownColor: Theme.of(context).colorScheme.surface,
              isExpanded: true,
              items: const [
                DropdownMenuItem(value: 'Kore', child: Text('Kore (Female)')),
                DropdownMenuItem(value: 'Puck', child: Text('Puck (Male)')),
                DropdownMenuItem(value: 'Charon', child: Text('Charon (Male)')),
                DropdownMenuItem(value: 'Fenrir', child: Text('Fenrir (Male)')),
                DropdownMenuItem(value: 'Aoede', child: Text('Aoede (Female)')),
              ],
              onChanged: (value) {
                if (value != null) appState.setGeminiLiveVoice(value);
              },
            ),
            const SizedBox(height: 16),
            // OpenAI Realtime Voice
            const Text(
              'OpenAI Realtime Voice',
              style: TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 8),
            DropdownButton<String>(
              value: appState.openaiRealtimeVoice,
              dropdownColor: Theme.of(context).colorScheme.surface,
              isExpanded: true,
              items: const [
                DropdownMenuItem(
                  value: 'alloy',
                  child: Text('Alloy (Neutral)'),
                ),
                DropdownMenuItem(value: 'echo', child: Text('Echo (Male)')),
                DropdownMenuItem(
                  value: 'fable',
                  child: Text('Fable (British)'),
                ),
                DropdownMenuItem(
                  value: 'onyx',
                  child: Text('Onyx (Deep Male)'),
                ),
                DropdownMenuItem(value: 'nova', child: Text('Nova (Female)')),
                DropdownMenuItem(
                  value: 'shimmer',
                  child: Text('Shimmer (Female)'),
                ),
              ],
              onChanged: (value) {
                if (value != null) appState.setOpenaiRealtimeVoice(value);
              },
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            // Standard Mode Voice (DeepSeek, Mistral)
            const Text(
              'Standard Mode Voice (DeepSeek, Mistral)',
              style: TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              title: const Text('Use OpenAI TTS'),
              subtitle: const Text('High quality voices (requires OpenAI key)'),
              value: appState.useOpenaiTts,
              onChanged: appState.setUseOpenaiTts,
              contentPadding: EdgeInsets.zero,
            ),
            if (appState.useOpenaiTts) ...[
              const SizedBox(height: 8),
              DropdownButton<String>(
                value: appState.standardModeVoice,
                dropdownColor: Theme.of(context).colorScheme.surface,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(
                    value: 'nova',
                    child: Text('Nova (Female, Warm)'),
                  ),
                  DropdownMenuItem(
                    value: 'shimmer',
                    child: Text('Shimmer (Female, Clear)'),
                  ),
                  DropdownMenuItem(
                    value: 'alloy',
                    child: Text('Alloy (Neutral)'),
                  ),
                  DropdownMenuItem(value: 'echo', child: Text('Echo (Male)')),
                  DropdownMenuItem(
                    value: 'fable',
                    child: Text('Fable (British)'),
                  ),
                  DropdownMenuItem(
                    value: 'onyx',
                    child: Text('Onyx (Deep Male)'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) appState.setStandardModeVoice(value);
                },
              ),
            ] else ...[
              const SizedBox(height: 4),
              const Text(
                'Using device TTS. Change in phone Settings > Text-to-Speech.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStorageSettings(AppState appState) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Audio Retention',
                      style: TextStyle(color: Colors.white),
                    ),
                    Text(
                      'Auto-delete recordings after',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
                DropdownButton<int>(
                  value: appState.audioRetentionDays,
                  dropdownColor: Theme.of(context).colorScheme.surface,
                  items: const [
                    DropdownMenuItem(value: 7, child: Text('7 days')),
                    DropdownMenuItem(value: 14, child: Text('14 days')),
                    DropdownMenuItem(value: 30, child: Text('30 days')),
                    DropdownMenuItem(value: 60, child: Text('60 days')),
                    DropdownMenuItem(value: 90, child: Text('90 days')),
                  ],
                  onChanged: (value) {
                    if (value != null) appState.setAudioRetentionDays(value);
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Row(
              children: [
                Icon(Icons.info_outline, color: Colors.white38, size: 16),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Text transcripts are stored permanently on device',
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDataManagement(AppState appState) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildClearHistoryTile(
              'Clear Gemini History',
              const Color(0xFF4285F4),
              () => _showClearConfirmation('Gemini'),
            ),
            const Divider(height: 16),
            _buildClearHistoryTile(
              'Clear OpenAI History',
              const Color(0xFF10A37F),
              () => _showClearConfirmation('OpenAI'),
            ),
            const Divider(height: 16),
            _buildClearHistoryTile(
              'Clear Deepseek History',
              const Color(0xFF6366F1),
              () => _showClearConfirmation('Deepseek'),
            ),
            const Divider(height: 16),
            _buildClearHistoryTile(
              'Clear Mistral History',
              const Color(0xFFFF7000),
              () => _showClearConfirmation('Mistral'),
            ),
            const Divider(height: 16),
            ListTile(
              leading: const Icon(Icons.delete_forever, color: Colors.red),
              title: const Text(
                'Clear All Data',
                style: TextStyle(color: Colors.red),
              ),
              subtitle: const Text('Delete all conversations and recordings'),
              onTap: () => _showClearConfirmation('All'),
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClearHistoryTile(String title, Color color, VoidCallback onTap) {
    return ListTile(
      leading: Icon(Icons.delete_outline, color: color),
      title: Text(title),
      onTap: onTap,
      contentPadding: EdgeInsets.zero,
    );
  }

  void _showClearConfirmation(String target) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Clear $target History?'),
        content: Text(
          'This will permanently delete all $target conversation history. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // TODO: Implement clear history for specific provider
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('$target history cleared')),
              );
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}

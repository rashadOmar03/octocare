import 'package:flutter/material.dart';
import '../l10n/localization.dart';
import '../services/api_service.dart';
import '../services/voice_service.dart';
import '../utils/ui_helpers.dart';
import 'voice_mic_button.dart';

class AiChatPanel extends StatefulWidget {
  final String welcomeMessage;
  final bool showDisclaimer;
  final String? initialChatId;

  const AiChatPanel({
    super.key,
    required this.welcomeMessage,
    this.showDisclaimer = false,
    this.initialChatId,
  });

  @override
  State<AiChatPanel> createState() => _AiChatPanelState();
}

class _AiChatPanelState extends State<AiChatPanel> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final VoiceService _voice = VoiceService.instance;
  final List<Map<String, String>> _messages = [];
  bool _isLoading = false;
  String? _conversationId;
  int _remainingMessages = 50;
  int _messageCount = 0;
  int _maxMessages = 50;

  @override
  void initState() {
    super.initState();
    if (widget.initialChatId != null) {
      _conversationId = widget.initialChatId;
      _loadExistingChat();
    } else {
      _messages.add({'role': 'assistant', 'content': widget.welcomeMessage});
    }
  }

  Future<void> _loadExistingChat() async {
    setState(() => _isLoading = true);
    try {
      final data = await ApiService.instance.get('/ai/chats/${widget.initialChatId}');
      final msgs = data['messages'] as List? ?? [];
      if (!mounted) return;
      setState(() {
        _messages.clear();
        for (final m in msgs) {
          _messages.add({
            'role': (m['role'] ?? 'user').toString(),
            'content': (m['content'] ?? '').toString(),
          });
        }
        _messageCount = data['message_count'] ?? 0;
        _remainingMessages = data['remaining_messages'] ?? 50;
        _maxMessages = data['max_messages'] ?? 50;
        _isLoading = false;
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.add({'role': 'assistant', 'content': widget.welcomeMessage});
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _voice.stopSpeaking();
    _voice.cancelRecording();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessageWithText(String rawText) async {
    final text = rawText.trim();
    if (text.isEmpty || _isLoading) return;

    if (_remainingMessages <= 0) {
      showErrorSnackBar(context, AppLocalizations.tr('chat_limit_reached'));
      return;
    }

    setState(() {
      _messages.add({'role': 'user', 'content': text});
      _isLoading = true;
    });
    _messageController.clear();
    _scrollToBottom();

    try {
      final hasArabic = RegExp(r'[\u0600-\u06FF]').hasMatch(text);
      final lang = hasArabic ? 'ar' : 'en';
      final body = <String, dynamic>{
        'message': text,
        'language': lang,
      };
      if (_conversationId != null) {
        body['conversation_id'] = _conversationId;
      }

      final response = await ApiService.instance.post('/ai/agent', body);
      final reply = (response['response'] ?? response['message'] ?? '').toString();
      if (!mounted) return;
      setState(() {
        _conversationId = response['conversation_id']?.toString();
        _remainingMessages = response['remaining_messages'] ?? _remainingMessages;
        _messageCount = response['message_count'] ?? _messageCount;
        _maxMessages = response['max_messages'] ?? _maxMessages;
        _messages.add({'role': 'assistant', 'content': reply.isNotEmpty ? reply : AppLocalizations.tr('no_data')});
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.add({'role': 'assistant', 'content': extractApiError(e)});
      });
    }

    if (mounted) setState(() => _isLoading = false);
    _scrollToBottom();
  }

  Future<void> _sendMessage() async {
    await _sendMessageWithText(_messageController.text);
  }

  Future<void> _sendVoiceMessage(String text) async {
    await _sendMessageWithText(text);
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _speakAssistant(int index, String text) async {
    if (_voice.speakingMessageIndex == index) {
      await _voice.stopSpeaking();
      setState(() {});
      return;
    }
    try {
      await _voice.speakText(
        text,
        language: AppLocalizations.currentLocale,
        messageIndex: index,
      );
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (widget.showDisclaimer)
          Container(
            padding: const EdgeInsets.all(12),
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.05),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 18, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    AppLocalizations.tr('disclaimer'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),

        // Remaining messages indicator
        if (_conversationId != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            child: Row(
              children: [
                Icon(Icons.chat_bubble_outline, size: 14,
                    color: _remainingMessages <= 5
                        ? Colors.red
                        : Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(
                  '${AppLocalizations.tr('messages_used')}: $_messageCount / $_maxMessages',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _remainingMessages <= 5
                        ? Colors.red
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),

        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(16),
            itemCount: _messages.length + (_isLoading ? 1 : 0),
            itemBuilder: (ctx, i) {
              if (i == _messages.length) {
                return _buildTypingIndicator();
              }
              return _buildMessageBubble(i, _messages[i]);
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, -2))],
          ),
          child: Row(
            children: [
              VoiceMicButton(
                controller: _messageController,
                onAutoSend: _sendVoiceMessage,
              ),
              Expanded(
                child: TextField(
                  controller: _messageController,
                  decoration: InputDecoration(
                    hintText: AppLocalizations.tr('type_message'),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
              const SizedBox(width: 8),
              CircleAvatar(
                backgroundColor: Theme.of(context).colorScheme.primary,
                child: IconButton(
                  icon: const Icon(Icons.send, color: Colors.white, size: 20),
                  onPressed: _isLoading ? null : _sendMessage,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMessageBubble(int index, Map<String, String> message) {
    final isUser = message['role'] == 'user';
    final content = message['content'] ?? '';
    final speaking = !isUser && _voice.speakingMessageIndex == index;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: isUser ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: isUser ? const Radius.circular(16) : const Radius.circular(4),
            bottomRight: isUser ? const Radius.circular(4) : const Radius.circular(16),
          ),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(
              content,
              style: TextStyle(
                color: isUser ? Colors.white : Theme.of(context).colorScheme.onSurface,
                height: 1.5,
              ),
            ),
            if (!isUser && content.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  tooltip: speaking ? AppLocalizations.tr('voice_stop') : AppLocalizations.tr('voice_listen'),
                  icon: Icon(
                    speaking ? Icons.stop_circle_outlined : Icons.volume_up_outlined,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  onPressed: () => _speakAssistant(index, content),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(width: 8),
            Text(AppLocalizations.tr('loading')),
          ],
        ),
      ),
    );
  }
}

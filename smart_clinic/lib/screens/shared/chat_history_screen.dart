import 'package:flutter/material.dart';
import '../../l10n/localization.dart';
import '../../services/api_service.dart';
import '../../utils/ui_helpers.dart';
import '../../widgets/ai_chat_panel.dart';

class ChatHistoryScreen extends StatefulWidget {
  final String role;
  final String welcomeMessage;
  final bool showDisclaimer;

  const ChatHistoryScreen({
    super.key,
    required this.role,
    required this.welcomeMessage,
    this.showDisclaimer = false,
  });

  @override
  State<ChatHistoryScreen> createState() => _ChatHistoryScreenState();
}

class _ChatHistoryScreenState extends State<ChatHistoryScreen> {
  List<Map<String, dynamic>> _chats = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadChats();
  }

  Future<void> _loadChats() async {
    setState(() => _loading = true);
    try {
      final data = await ApiService.instance.get('/ai/chats');
      if (!mounted) return;
      setState(() {
        final list = data is List ? data : (data is Map ? (data['items'] as List? ?? []) : []);
        _chats = list.map((e) => Map<String, dynamic>.from(e)).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _openChat({String? chatId}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _ChatViewScreen(
          chatId: chatId,
          welcomeMessage: widget.welcomeMessage,
          showDisclaimer: widget.showDisclaimer,
          onDeleted: _loadChats,
        ),
      ),
    ).then((_) => _loadChats());
  }

  Future<bool> _confirmDeleteChat(String chatId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.tr('delete')),
        content: Text(AppLocalizations.tr('delete_chat_confirm')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(AppLocalizations.tr('cancel'))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(AppLocalizations.tr('delete'), style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return false;
    try {
      await ApiService.instance.delete('/ai/chats/$chatId');
      if (mounted) {
        showSuccessSnackBar(context, AppLocalizations.tr('chat_deleted'));
      }
      return true;
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e);
      return false;
    }
  }

  Future<void> _deleteChat(String chatId) async {
    final deleted = await _confirmDeleteChat(chatId);
    if (deleted) _loadChats();
  }

  String _formatDate(String? iso) {
    if (iso == null) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inMinutes < 1) return AppLocalizations.tr('just_now');
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.tr('chat_history')),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openChat(),
        icon: const Icon(Icons.add),
        label: Text(AppLocalizations.tr('new_chat')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _chats.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.chat_outlined, size: 64, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3)),
                      const SizedBox(height: 16),
                      Text(
                        AppLocalizations.tr('no_chats_yet'),
                        style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        AppLocalizations.tr('start_new_chat_hint'),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadChats,
                  child: ListView.separated(
                    padding: const EdgeInsets.only(top: 8, bottom: 80),
                    itemCount: _chats.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (ctx, i) {
                      final chat = _chats[i];
                      final summary = chat['summary'] ?? 'Chat';
                      final msgCount = chat['message_count'] ?? 0;
                      final remaining = chat['remaining_messages'] ?? 50;
                      final maxMsgs = chat['max_messages'] ?? 50;
                      final updatedAt = _formatDate(chat['updated_at']?.toString());

                      return Dismissible(
                        key: Key(chat['id']),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          color: Colors.red,
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 24),
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        confirmDismiss: (_) => _confirmDeleteChat(chat['id']),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: remaining <= 5
                                ? Colors.red.withValues(alpha: 0.1)
                                : theme.colorScheme.primary.withValues(alpha: 0.1),
                            child: Icon(
                              Icons.chat_bubble_outline,
                              color: remaining <= 5 ? Colors.red : theme.colorScheme.primary,
                              size: 20,
                            ),
                          ),
                          title: Text(
                            summary,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            '$msgCount / $maxMsgs ${AppLocalizations.tr('messages_label')}  $updatedAt',
                            style: theme.textTheme.bodySmall,
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (remaining <= 5)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '$remaining left',
                                    style: theme.textTheme.labelSmall?.copyWith(color: Colors.red),
                                  ),
                                ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.red),
                                tooltip: AppLocalizations.tr('delete'),
                                onPressed: () => _deleteChat(chat['id']),
                              ),
                              const Icon(Icons.chevron_right, size: 20),
                            ],
                          ),
                          onTap: () => _openChat(chatId: chat['id']),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

class _ChatViewScreen extends StatefulWidget {
  final String? chatId;
  final String welcomeMessage;
  final bool showDisclaimer;
  final VoidCallback? onDeleted;

  const _ChatViewScreen({
    this.chatId,
    required this.welcomeMessage,
    required this.showDisclaimer,
    this.onDeleted,
  });

  @override
  State<_ChatViewScreen> createState() => _ChatViewScreenState();
}

class _ChatViewScreenState extends State<_ChatViewScreen> {
  Future<void> _deleteCurrentChat() async {
    final chatId = widget.chatId;
    if (chatId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.tr('delete')),
        content: Text(AppLocalizations.tr('delete_chat_confirm')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(AppLocalizations.tr('cancel'))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(AppLocalizations.tr('delete'), style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await ApiService.instance.delete('/ai/chats/$chatId');
      widget.onDeleted?.call();
      if (mounted) {
        showSuccessSnackBar(context, AppLocalizations.tr('chat_deleted'));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.tr('ai_assistant')),
        actions: [
          if (widget.chatId != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              color: Colors.red,
              tooltip: AppLocalizations.tr('delete'),
              onPressed: _deleteCurrentChat,
            ),
        ],
      ),
      body: AiChatPanel(
        welcomeMessage: widget.welcomeMessage,
        showDisclaimer: widget.showDisclaimer,
        initialChatId: widget.chatId,
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../../l10n/localization.dart';
import '../../services/api_service.dart';
import '../../models/notification_model.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_widget.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<NotificationModel> _notifications = [];
  bool _isLoading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final response = await ApiService.instance.get('/patients/notifications');
      final List<dynamic> data = response is List ? response : (response['results'] ?? []);
      _notifications = data.map((e) => NotificationModel.fromJson(Map<String, dynamic>.from(e))).toList();
    } catch (e) {
      _notifications = [];
      _loadError = e.toString();
    }
    setState(() => _isLoading = false);
  }

  Future<void> _markAsRead(String id) async {
    try {
      await ApiService.instance.put('/patients/notifications/$id/read', {});
      _loadNotifications();
    } catch (_) {}
  }

  Future<void> _markAllRead() async {
    for (final n in _notifications.where((n) => n.isRead != true)) {
      if (n.id != null) await _markAsRead(n.id!);
    }
  }

  Future<void> _deleteNotification(String id) async {
    try {
      await ApiService.instance.delete('/patients/notifications/$id');
      _loadNotifications();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final unreadCount = _notifications.where((n) => n.isRead != true).length;

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.tr('notifications')),
        actions: [
          if (unreadCount > 0)
            TextButton.icon(
              onPressed: _markAllRead,
              icon: const Icon(Icons.done_all, size: 18),
              label: Text(AppLocalizations.tr('mark_read')),
            ),
        ],
      ),
      body: _isLoading
          ? const LoadingWidget()
          : _loadError != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.notifications_off, size: 64, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3)),
                      const SizedBox(height: 16),
                      Text(AppLocalizations.tr('no_notifications')),
                    ],
                  ),
                )
              : _notifications.isEmpty
                  ? EmptyState(icon: Icons.notifications_off, message: AppLocalizations.tr('no_notifications'))
              : RefreshIndicator(
                  onRefresh: _loadNotifications,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: _notifications.length,
                    itemBuilder: (ctx, i) {
                      final n = _notifications[i];
                      final isUnread = n.isRead != true;
                      return Dismissible(
                        key: Key('${n.id}'),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          color: Theme.of(context).colorScheme.error,
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 16),
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        onDismissed: (_) {
                          if (n.id != null) _deleteNotification(n.id!);
                        },
                        child: Card(
                          color: isUnread
                              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.08)
                              : null,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: isUnread
                                ? BorderSide(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3))
                                : BorderSide.none,
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: isUnread
                                  ? Theme.of(context).colorScheme.primary
                                  : const Color(0xFFE0E0E0),
                              child: Icon(
                                isUnread ? Icons.notifications_active : Icons.notifications_none,
                                color: isUnread ? Colors.white : const Color(0xFF757575),
                                size: 20,
                              ),
                            ),
                            title: Text(
                              n.title ?? '',
                              style: TextStyle(
                                fontWeight: isUnread ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                Text(n.message ?? ''),
                                const SizedBox(height: 4),
                                Text(
                                  n.createdAt ?? '',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                                  ),
                                ),
                              ],
                            ),
                            trailing: isUnread
                                ? IconButton(
                                    icon: Icon(Icons.mark_email_read, size: 20, color: Theme.of(context).colorScheme.primary),
                                    onPressed: () {
                                      if (n.id != null) _markAsRead(n.id!);
                                    },
                                  )
                                : null,
                            isThreeLine: true,
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

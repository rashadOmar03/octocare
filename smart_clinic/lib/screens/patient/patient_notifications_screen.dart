import 'package:flutter/material.dart';
import '../../l10n/localization.dart';
import '../../services/api_service.dart';
import '../../models/notification_model.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_widget.dart';

class PatientNotificationsScreen extends StatefulWidget {
  const PatientNotificationsScreen({super.key});

  @override
  State<PatientNotificationsScreen> createState() => _PatientNotificationsScreenState();
}

class _PatientNotificationsScreenState extends State<PatientNotificationsScreen> {
  List<NotificationModel> _notifications = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    setState(() => _isLoading = true);
    try {
      final response = await ApiService.instance.get('/patients/notifications');
      final List<dynamic> data = response is List ? response : (response['results'] ?? []);
      _notifications = data.map((e) => NotificationModel.fromJson(e)).toList();
    } catch (_) {}
    setState(() => _isLoading = false);
  }

  Future<void> _markAsRead(String id) async {
    try {
      await ApiService.instance.put('/patients/notifications/$id/read', {});
      _loadNotifications();
    } catch (_) {}
  }

  Future<void> _deleteNotification(String id) async {
    try {
      await ApiService.instance.delete('/patients/notifications/$id');
      _loadNotifications();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.tr('notifications')),
        actions: [
          if (_notifications.isNotEmpty)
            PopupMenuButton(
              itemBuilder: (ctx) => [
                PopupMenuItem(
                  child: Text(AppLocalizations.tr('mark_read')),
                  onTap: () async {
                    for (final n in _notifications.where((n) => n.isRead != true)) {
                      if (n.id != null) await _markAsRead(n.id!);
                    }
                  },
                ),
              ],
            ),
        ],
      ),
      body: _isLoading
          ? const LoadingWidget()
          : _notifications.isEmpty
              ? EmptyState(icon: Icons.notifications_off, message: AppLocalizations.tr('no_notifications'))
              : RefreshIndicator(
                  onRefresh: _loadNotifications,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: _notifications.length,
                    itemBuilder: (ctx, i) {
                      final n = _notifications[i];
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
                          color: n.isRead == true ? null : Theme.of(context).colorScheme.primary.withValues(alpha: 0.05),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: n.isRead == true
                                  ? const Color(0xFFE0E0E0)
                                  : Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                              child: Icon(
                                Icons.notifications,
                                color: n.isRead == true ? const Color(0xFF757575) : Theme.of(context).colorScheme.primary,
                              ),
                            ),
                            title: Text(
                              n.title ?? '',
                              style: TextStyle(fontWeight: n.isRead == true ? FontWeight.normal : FontWeight.bold),
                            ),
                            subtitle: Text(n.message ?? ''),
                            trailing: n.isRead != true
                                ? IconButton(
                                    icon: const Icon(Icons.mark_email_read, size: 20),
                                    onPressed: () {
                                      if (n.id != null) _markAsRead(n.id!);
                                    },
                                  )
                                : null,
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

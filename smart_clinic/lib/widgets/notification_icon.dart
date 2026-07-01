import 'package:flutter/material.dart';
import '../services/api_service.dart';

class NotificationIcon extends StatefulWidget {
  final VoidCallback onPressed;

  const NotificationIcon({super.key, required this.onPressed});

  @override
  State<NotificationIcon> createState() => NotificationIconState();
}

class NotificationIconState extends State<NotificationIcon> {
  int _unreadCount = 0;

  @override
  void initState() {
    super.initState();
    _fetchCount();
  }

  Future<void> _fetchCount() async {
    try {
      final response = await ApiService.instance.get('/patients/notifications');
      final List<dynamic> data = response is List ? response : (response['results'] ?? []);
      final count = data.where((n) => n['is_read'] != true).length;
      if (mounted) setState(() => _unreadCount = count);
    } catch (_) {
      if (mounted) setState(() => _unreadCount = 0);
    }
  }

  void refresh() => _fetchCount();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        IconButton(
          icon: Icon(
            _unreadCount > 0 ? Icons.notifications_active : Icons.notifications_outlined,
            color: _unreadCount > 0 ? Theme.of(context).colorScheme.primary : null,
          ),
          onPressed: widget.onPressed,
        ),
        if (_unreadCount > 0)
          Positioned(
            right: 6,
            top: 6,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(10),
              ),
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
              child: Text(
                _unreadCount > 99 ? '99+' : '$_unreadCount',
                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }
}

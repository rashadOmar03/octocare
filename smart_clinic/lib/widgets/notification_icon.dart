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

  Color _badgeColor(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return scheme.brightness == Brightness.dark
        ? const Color(0xFFFF8A65)
        : const Color(0xFFD84315);
  }

  @override
  Widget build(BuildContext context) {
    final iconColor = IconTheme.of(context).color ?? Theme.of(context).appBarTheme.foregroundColor ?? Colors.white;

    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: Badge(
        isLabelVisible: _unreadCount > 0,
        offset: const Offset(-2, 2),
        backgroundColor: _badgeColor(context),
        textColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        label: Text(
          _unreadCount > 99 ? '99+' : '$_unreadCount',
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, height: 1.1),
        ),
        child: IconButton(
          icon: Icon(
            _unreadCount > 0 ? Icons.notifications_rounded : Icons.notifications_outlined,
            color: iconColor,
          ),
          onPressed: widget.onPressed,
        ),
      ),
    );
  }
}

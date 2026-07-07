import 'package:flutter/material.dart';
import '../services/api_service.dart';

class NotificationIcon extends StatefulWidget {
  final VoidCallback onPressed;
  final Color? iconColor;

  const NotificationIcon({super.key, required this.onPressed, this.iconColor});

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

  Color _iconColor(BuildContext context) {
    if (widget.iconColor != null) return widget.iconColor!;
    final appBar = Theme.of(context).appBarTheme;
    if (appBar.foregroundColor != null) return appBar.foregroundColor!;
    return Theme.of(context).brightness == Brightness.dark ? Colors.white : const Color(0xFF212121);
  }

  @override
  Widget build(BuildContext context) {
    final iconColor = _iconColor(context);
    final bellIcon = Icon(
      _unreadCount > 0 ? Icons.notifications_rounded : Icons.notifications_outlined,
      color: iconColor,
    );

    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: IconButton(
        tooltip: MaterialLocalizations.of(context).showMenuTooltip,
        style: IconButton.styleFrom(foregroundColor: iconColor),
        onPressed: widget.onPressed,
        icon: Badge(
          isLabelVisible: _unreadCount > 0,
          offset: const Offset(4, -4),
          backgroundColor: _badgeColor(context),
          textColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          label: Text(
            _unreadCount > 99 ? '99+' : '$_unreadCount',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, height: 1.1),
          ),
          child: bellIcon,
        ),
      ),
    );
  }
}

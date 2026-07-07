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
    final appBarFg = Theme.of(context).appBarTheme.foregroundColor;
    if (appBarFg != null) return appBarFg;
    return Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.white;
  }

  Color _badgeBorderColor(BuildContext context) {
    final appBarBg = Theme.of(context).appBarTheme.backgroundColor;
    if (appBarBg != null) return appBarBg;
    return Theme.of(context).colorScheme.surface;
  }

  @override
  Widget build(BuildContext context) {
    final iconColor = _iconColor(context);
    final badgeColor = _badgeColor(context);
    final badgeBorder = _badgeBorderColor(context);

    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: IconButton(
        tooltip: 'Notifications',
        onPressed: widget.onPressed,
        icon: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Icon(Icons.notifications, color: iconColor, size: 26),
            if (_unreadCount > 0)
              Positioned(
                right: -2,
                top: -4,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: badgeColor,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: badgeBorder, width: 1.5),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _unreadCount > 99 ? '99+' : '$_unreadCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

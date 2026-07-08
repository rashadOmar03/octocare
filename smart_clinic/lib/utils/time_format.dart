import 'package:intl/intl.dart';
import '../l10n/localization.dart';

class TimeFormat {
  /// Parse API timestamps stored as UTC (often without a trailing Z).
  static DateTime parseServerUtc(String? iso) {
    if (iso == null || iso.isEmpty) return DateTime.now();
    var s = iso.trim();
    final hasZone = s.endsWith('Z') ||
        RegExp(r'[+-]\d{2}:\d{2}$').hasMatch(s) ||
        RegExp(r'[+-]\d{4}$').hasMatch(s);
    if (!hasZone) s = '${s}Z';
    return DateTime.parse(s).toLocal();
  }

  /// Real local clock time for chat history (e.g. "10:48 PM" or "8 Jul 2026, 10:48 PM").
  static String formatChatTimestamp(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    final dt = parseServerUtc(iso);
    final locale = AppLocalizations.currentLocale == 'ar' ? 'ar' : 'en_US';
    final now = DateTime.now();
    final sameDay = dt.year == now.year && dt.month == now.month && dt.day == now.day;
    if (sameDay) {
      return DateFormat('h:mm a', locale).format(dt);
    }
    return DateFormat('d MMM y, h:mm a', locale).format(dt);
  }

  /// Display 24h HH:mm as 12h e.g. "2:30 PM". API still uses 24h strings.
  static String format24To12(String? time24) {
    if (time24 == null || time24.isEmpty) return '-';
    final parts = time24.split(':');
    if (parts.length < 2) return time24;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return time24;
    final dt = DateTime(2000, 1, 1, hour, minute);
    final locale = AppLocalizations.currentLocale == 'ar' ? 'ar' : 'en_US';
    return DateFormat('h:mm a', locale).format(dt);
  }
}

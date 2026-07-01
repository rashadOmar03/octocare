import 'package:intl/intl.dart';
import '../l10n/localization.dart';

class TimeFormat {
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

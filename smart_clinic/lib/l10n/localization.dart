import 'app_en.dart';
import 'app_ar.dart';

class AppLocalizations {
  static String currentLocale = 'en';

  static String tr(String key) {
    if (currentLocale == 'ar') {
      return AppStringsAr.strings[key] ?? AppStringsEn.strings[key] ?? key;
    }
    return AppStringsEn.strings[key] ?? key;
  }

  /// Translates stored API values (e.g. male → ذكر) while leaving free text unchanged.
  static String trValue(dynamic value, {String fallback = '-'}) {
    if (value == null || value.toString().trim().isEmpty) return fallback;
    final raw = value.toString().trim();
    final key = raw.toLowerCase();
    if (AppStringsEn.strings.containsKey(key) ||
        (currentLocale == 'ar' && AppStringsAr.strings.containsKey(key))) {
      return tr(key);
    }
    return raw;
  }
}

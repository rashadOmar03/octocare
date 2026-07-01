import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/localization.dart';

class LocaleProvider extends ChangeNotifier {
  Locale _locale = const Locale('en');

  Locale get locale => _locale;
  bool get isArabic => _locale.languageCode == 'ar';

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final langCode = prefs.getString('locale') ?? 'en';
    _locale = Locale(langCode);
    AppLocalizations.currentLocale = langCode;
    notifyListeners();
  }

  Future<void> toggleLocale() async {
    final newLang = _locale.languageCode == 'en' ? 'ar' : 'en';
    _locale = Locale(newLang);
    AppLocalizations.currentLocale = newLang;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('locale', newLang);
    notifyListeners();
  }

  Future<void> setLocale(String langCode) async {
    _locale = Locale(langCode);
    AppLocalizations.currentLocale = langCode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('locale', langCode);
    notifyListeners();
  }
}

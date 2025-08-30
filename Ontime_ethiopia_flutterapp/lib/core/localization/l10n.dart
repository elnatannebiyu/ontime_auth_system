import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppLanguage { en, am }

class LocalizationController extends ChangeNotifier {
  static const _keyLang = 'app_language';
  AppLanguage _lang = AppLanguage.en;

  AppLanguage get language => _lang;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_keyLang);
    if (code == 'am') {
      _lang = AppLanguage.am;
    } else if (code == 'en') {
      _lang = AppLanguage.en;
    }
    notifyListeners();
  }

  Future<void> setLanguage(AppLanguage lang) async {
    if (_lang == lang) return;
    _lang = lang;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLang, lang == AppLanguage.en ? 'en' : 'am');
  }

  Future<void> toggleLanguage() => setLanguage(_lang == AppLanguage.en ? AppLanguage.am : AppLanguage.en);

  String t(String key) {
    const en = {
      'home': 'Home',
      'channels': 'Channels',
      'logout': 'Logout',
      'welcome': 'Welcome',
      'for_you': 'For You',
      'trending': 'Trending',
      'sports': 'Sports',
      'kids': 'Kids',
      'browse_channels': 'Browse channels',
      'continue_watching': 'Continue watching',
      'see_all': 'See all',
      'trending_now': 'Trending now',
      'new_releases': 'New releases',
      'go_live': 'Go Live',
      'play': 'Play',
      'live': 'LIVE',
      'now_playing': 'Now Playing',
      'settings': 'Settings',
      'appearance': 'Appearance',
      'system': 'System',
      'light': 'Light',
      'dark': 'Dark',
      'language': 'Language',
      'profile': 'Profile',
      'about': 'About',
      'switch_language': 'Switch language',
    };
    const am = {
      'home': 'መነሻ',
      'channels': 'ቻናሎች',
      'logout': 'መውጣት',
      'welcome': 'እንኳን በደህና መጣህ/ሽ',
      'for_you': 'ለእርስዎ',
      'trending': 'ታዋቂ',
      'sports': 'ስፖርት',
      'kids': 'ለህፃናት',
      'browse_channels': 'ቻናሎችን ይመልከቱ',
      'continue_watching': 'ቀጥሎ የሚታይ',
      'see_all': 'ሁሉንም ይመልከቱ',
      'trending_now': 'አሁን ታዋቂ',
      'new_releases': 'አዳዲስ መውጫዎች',
      'go_live': 'በቀጥታ መስጠት',
      'play': 'አጫውት',
      'live': 'ቀጥታ',
      'now_playing': 'አሁን የሚጫወት',
      'settings': 'ማሰናጃ',
      'appearance': 'አቀራረብ',
      'system': 'ሲስተም',
      'light': 'ብርሃን',
      'dark': 'ጨለማ',
      'language': 'ቋንቋ',
      'profile': 'መገለጫ',
      'about': 'ስለ መተግበሪያው',
      'switch_language': 'ቋንቋ መቀየር',
    };
    final dict = _lang == AppLanguage.en ? en : am;
    return dict[key] ?? key;
  }
}

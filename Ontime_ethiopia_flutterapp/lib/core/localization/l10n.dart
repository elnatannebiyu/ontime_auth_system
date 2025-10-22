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
      'Shows': 'Shows',
      'trending': 'Trending',
      'sports': 'Sports',
      'kids': 'Kids',
      'Shorts': 'Shorts',
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
      // Channels page
      'offline_mode': 'Offline mode',
      'showing_cached': 'Showing cached channels until you reconnect.',
      'retry': 'Retry',
      'details': 'Details',
      'connection_details': 'Connection details',
      'server': 'Server',
      'tenant': 'Tenant',
      'tip_pull_refresh': 'Tip: Pull to refresh, or check that your device can reach the server.',
      'loading': 'Loading…',
      'no_playlists': 'No playlists',
      'no_videos': 'No videos',
      'refresh_playlists': 'Refresh playlists',
      // Channel details modal
      'channel_details': 'Channel details',
      'info': 'Info',
      'close': 'Close',
      'tenant_label': 'Tenant',
      'id_slug': 'Id slug',
      'default_locale': 'Default locale',
      'name_am': 'Name am',
      'name_en': 'Name en',
      'aliases': 'Aliases',
      'youtube_handle': 'YouTube handle',
      'channel_handle': 'Channel handle',
      'youtube_channel_id': 'YouTube channel id',
      'resolved_channel_id': 'Resolved channel ID',
      'images': 'Images',
      'sources': 'Sources',
      'genres': 'Genres',
      'language_label': 'Language',
      'country': 'Country',
      'tags': 'Tags',
      'is_active': 'Is active',
      'platforms': 'Platforms',
      'drm_required': 'DRM required',
      'sort_order': 'Sort order',
      'featured': 'Featured',
      'rights': 'Rights',
      'audit': 'Audit',
      'uid': 'UID',
      'created_at': 'Created at',
      'updated_at': 'Updated at',
      // Update / dialogs
      'update_required_title': 'Update Required',
      'update_required_body': 'Please update the app to continue.',
      'update_cta': 'Update',
      'open_link_manually': 'Open this link manually',
      'link_copied': 'Link copied to clipboard',
      'copy': 'Copy',
      'close_dialog': 'Close',
      'session_expired': 'Session expired. Please sign in again.',
      // Common UI
      'search': 'Search',
      'menu': 'Menu',
      'you_are_offline': 'You are offline',
      'some_actions_offline': 'Some actions may not work until you reconnect.',
      'coming_soon': 'coming soon',
    };
    const am = {
      'home': 'መነሻ',
      'channels': 'ቻናሎች',
      'logout': 'መውጣት',
      'welcome': 'እንኳን በደህና መጣህ/ሽ',
      'for_you': 'ለእርስዎ',
      'Shows': 'ተከታታይ',
      'trending': 'ታዋቂ',
      'sports': 'ስፖርት',
      'kids': 'ለህፃናት',
      'Shorts': 'አጭር ቪዲዮዎች',
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
      // Channels page
      'offline_mode': 'ከመስመር ውጭ ሁነታ',
      'showing_cached': 'እስከሚገናኙ ድረስ የተቀመጡ ቻናሎች እየታዩ ናቸው።',
      'retry': 'እንደገና ሞክር',
      'details': 'ዝርዝሮች',
      'connection_details': 'የግንኙነት ዝርዝር',
      'server': 'ሰርቨር',
      'tenant': 'ተከራይ',
      'tip_pull_refresh': 'መጀመሪያ ለማደስ ይጎትቱ ወይም መሣሪያዎ ሰርቨሩን መድረስ እንደሚችል ያረጋግጡ።',
      'loading': 'በመጫን ላይ…',
      'no_playlists': 'ፕሌይሊስት የለም',
      'no_videos': 'ቪዲዮዎች የሉም',
      'refresh_playlists': 'ፕሌይሊስቶችን አድስ',
      // Channel details modal
      'channel_details': 'የቻናል ዝርዝር',
      'info': 'መረጃ',
      'close': 'ዝጋ',
      'tenant_label': 'ተከራይ',
      'id_slug': 'Id slug',
      'default_locale': 'Default locale',
      'name_am': 'ስም (አማርኛ)',
      'name_en': 'ስም (እንግሊዝኛ)',
      'aliases': 'አስተናጋጆች',
      'youtube_handle': 'ዩቲዩብ ሃንድል',
      'channel_handle': 'ቻናል ሃንድል',
      'youtube_channel_id': 'ዩቲዩብ ቻናል መለያ',
      'resolved_channel_id': 'የተፈታ መለያ',
      'images': 'ምስሎች',
      'sources': 'ምንጮች',
      'genres': 'ዘይቤዎች',
      'language_label': 'ቋንቋ',
      'country': 'አገር',
      'tags': 'መለያ ቃላት',
      'is_active': 'ንቁ ነው',
      'platforms': 'መድረኮች',
      'drm_required': 'DRM ያስፈልጋል',
      'sort_order': 'የመለያየት ቅደም ተከተል',
      'featured': 'ተለይቶ ታይ',
      'rights': 'መብቶች',
      'audit': 'ኦዲት',
      'uid': 'UID',
      'created_at': 'ተፈጠረ በ',
      'updated_at': 'ተዘምኗል በ',
      // Update / dialogs
      'update_required_title': 'ዝማኔ ያስፈልጋል',
      'update_required_body': 'መቀጠል ለማድረግ መተግበሪያውን እባክዎ ያዘምኑ።',
      'update_cta': 'አዘምን',
      'open_link_manually': 'ይህን አገናኝ በእጅ ይክፈቱ',
      'link_copied': 'አገናኙ ወደ ቅጂ ተቀምጧል',
      'copy': 'ቅጂ',
      'close_dialog': 'ዝጋ',
      'session_expired': 'ክፍለ ጊዜዎ አልፏል። እባክዎ እንደገና ይግቡ።',
      // Common UI
      'search': 'ፈልግ',
      'menu': 'ምናሌ',
      'you_are_offline': 'ከመስመር ውጭ ነዎት',
      'some_actions_offline': 'እስክትገናኙ ድረስ አንዳንድ እርምጃዎች ላይ ሊሰሩ አይችሉም።',
      'coming_soon': 'ለቅርብ ጊዜ',
    };
    final dict = _lang == AppLanguage.en ? en : am;
    return dict[key] ?? key;
  }
}

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppLanguage { en, am, om }

class LocalizationController extends ChangeNotifier {
  static const _keyLang = 'app_language';
  AppLanguage _lang = AppLanguage.en;

  AppLanguage get language => _lang;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_keyLang);
    if (code == 'am') {
      _lang = AppLanguage.am;
    } else if (code == 'om') {
      _lang = AppLanguage.om;
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
    await prefs.setString(
      _keyLang,
      lang == AppLanguage.en
          ? 'en'
          : lang == AppLanguage.am
              ? 'am'
              : 'om',
    );
  }

  Future<void> toggleLanguage() => setLanguage(
        _lang == AppLanguage.en
            ? AppLanguage.am
            : _lang == AppLanguage.am
                ? AppLanguage.om
                : AppLanguage.en,
      );

  String t(String key) {
    const en = {
      'home': 'Home',
      'channels': 'Channels',
      'logout': 'Logout',
      'welcome': 'Welcome',
      'for_you': 'For You',
      'Shows': 'Shows',
      'Categories': 'Categories',
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
      'live': 'Live',
      'now_playing': 'Now Playing',
      // Login page
      'welcome_back': 'Welcome back',
      'login_subtitle': 'Sign in with your Google account',
      'toggle_dark_mode': 'Toggle dark mode',
      'create_account': 'Create an account',
      'enter_valid_email': 'Enter a valid email address.',
      'login_failed': 'Login failed',
      'incorrect_email_password': 'Incorrect email or password.',
      'too_many_attempts':
          'Too many attempts. Please wait a minute and try again.',
      'account_locked':
          'Account temporarily locked due to failed attempts. Try again later.',
      'generic_error': 'Something went wrong. Please try again.',
      'email_or_username': 'Email',
      'email_or_username_required': 'Enter your email',
      'password_label': 'Password',
      'password_required': 'Enter password',
      'sign_in': 'Sign in',
      'use_phone_coming_soon': 'Use phone (coming soon)',
      'choose_language': 'Choose language',
      'create_new_account_title': 'Create new account?',
      'create_new_account_body':
          'No account exists for this Google account. Create one now?',
      'dialog_cancel': 'Cancel',
      'dialog_create': 'Create',
      'apple_signin_coming_soon': 'Apple sign-in coming soon.',
      'google_signin_failed': 'Google sign-in failed. Please try again.',
      'apple_signin_failed': 'Apple sign-in failed. Please try again.',
      'sign_in_or_sign_up_with_google': 'Sign in or Sign up with Google',
      'sign_in_or_sign_up_with_apple': 'Sign in or Sign up with Apple',
      'tv': 'TV',
      'radio': 'Radio',
      'live_tv': 'Live TV',
      'settings': 'Settings',
      'appearance': 'Appearance',
      'system': 'System',
      'light': 'Light',
      'dark': 'Dark',
      'language': 'Language',
      'profile': 'Profile',
      'profile_settings': 'Profile',
      'about': 'About',
      'switch_language': 'Switch language',
      'english': 'English',
      'amharic': 'Amharic',
      'oromo': 'Oromo',
      // Settings page
      'security': 'Security',
      'active_sessions': 'Active sessions',
      'active_sessions_subtitle': 'View and manage your active sessions',
      'session_security': 'Session security',
      'session_security_subtitle': 'Configure security settings',
      'notifications_section': 'Notifications',
      'notification_inbox': 'Notification inbox',
      'notification_inbox_subtitle':
          'View announcements and push notifications',
      // Channels page
      'offline_mode': 'Offline mode',
      'showing_cached': 'Showing cached channels until you reconnect.',
      'retry': 'Retry',
      'details': 'Details',
      'connection_details': 'Connection details',
      'server': 'Server',
      'tenant': 'Tenant',
      'tip_pull_refresh':
          'Tip: Pull to refresh, or check that your device can reach the server.',
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
      'all': 'All',
      'menu': 'Menu',
      'you_are_offline': 'You are offline',
      'some_actions_offline': 'Some actions may not work until you reconnect.',
      'coming_soon': 'coming soon',
      // Profile page
      'profile_details': 'Profile details',
      'first_name': 'First name',
      'last_name': 'Last name',
      'edit': 'Edit',
      'cancel': 'Cancel',
      'save_changes': 'Save changes',
      'sign_out': 'Sign out',
      'danger_zone': 'Danger zone',
      'delete_account': 'Delete account',
      'delete_account_title': 'Delete account',
      'delete_account_body':
          'This will deactivate your account, remove your personal profile details, and log you out from all devices. Some activity may remain in anonymized form.',
      'delete_account_not_implemented':
          'Account deletion is not implemented yet. Please contact support.',
      'delete_account_success':
          'Your account has been deleted and you have been logged out.',
      'delete_account_error':
          'Failed to delete your account. Please try again.',
      'profile_load_error': 'Problem loading profile',
      'profile_update_success': 'Profile updated',
      'profile_update_error': 'Failed to update profile',
      // Email verification
      'email_not_verified_banner':
          'Your email is not verified. Some features may be limited.',
      'verify_now': 'Verify now',
      'verification_email_sent': 'Verification email sent. Check your inbox.',
      'verification_email_failed':
          'Could not send verification email. Please try again.',
      // Password & security
      'password_status_enabled': 'Password: enabled',
      'password_status_not_set': 'Password: not set',
      'password_manage_requires_verified_email':
          'Verify your email to manage your password.',
      'enable_password': 'Set password',
      'disable_password': 'Disable password',
      'password_enabled_logged_out':
          'Password enabled. You have been logged out from all devices.',
      'password_disabled_logged_out':
          'Password disabled. You have been logged out from all devices.',
      // Forgot password
      'forgot_password': 'Forgot password?',
      'password_reset_email_sent_generic':
          'If an account with a verified email exists, a reset link has been sent.',
    };
    const am = {
      'home': 'መነሻ',
      'channels': 'ቻናሎች',
      'logout': 'ውጣ',
      'welcome': 'እንኳን በደህና መጡ',
      'for_you': 'ለእርስዎ',
      'Shows': 'ተከታታይ ትርኢቶች',
      'Categories': 'ምድቦች',
      'trending': 'ታዋቂ',
      'sports': 'ስፖርት',
      'kids': 'ህፃናት',
      'Shorts': 'አጭር ቪዲዮዎች',
      'browse_channels': 'ቻናሎችን ይዘርዝሩ',
      'continue_watching': 'ቀጥሎ ይመልከቱ',
      'see_all': 'ሁሉንም ይመልከቱ',
      'trending_now': 'አሁን ታዋቂ',
      'new_releases': 'አዳዲስ መውጫዎች',
      'go_live': 'ቀጥታ ጀምር',
      'play': 'አጫውት',
      'live': 'ቀጥታ',
      'now_playing': 'አሁን የሚጫወተው',
      // Login page
      'welcome_back': 'እንኳን በደህና መለሱ',
      'login_subtitle': 'በGoogle መለያዎ ይግቡ',
      'toggle_dark_mode': 'የጨለማ ገጽታ ቀይር',
      'create_account': 'መለያ ይፍጠሩ',
      'enter_valid_email': 'ትክክለኛ ኢሜል ያስገቡ።',
      'login_failed': 'መግባት አልተሳካም',
      'incorrect_email_password': 'የተሳሳተ ኢሜል ወይም ፓስዎርድ።',
      'too_many_attempts': 'ብዙ ሙከራዎች ተደርገዋል። እባክዎ ጥቂት ጊዜ ቆይተው እንደገና ይሞክሩ።',
      'account_locked': 'በተደጋጋሚ ስህተት ምክንያት መለያዎ ጊዜያዊ ተቆልፏል። በኋላ ይሞክሩ።',
      'generic_error': 'ጉዳይ ተፈጥሯል። እባክዎ እንደገና ይሞክሩ።',
      'email_or_username': 'ኢሜል ወይም የተጠቃሚ ስም',
      'email_or_username_required': 'ኢሜል ወይም የተጠቃሚ ስም ያስገቡ',
      'password_label': 'ፓስዎርድ',
      'password_required': 'ፓስዎርድ ያስገቡ',
      'sign_in': 'ይግቡ',
      'use_phone_coming_soon': 'ስልክ መጠቀም (በቅርብ ጊዜ)',
      'choose_language': 'ቋንቋ ይምረጡ',
      'create_new_account_title': 'አዲስ መለያ ይፍጠሩ?',
      'create_new_account_body': 'ለዚህ የGoogle መለያ መዝገብ አልተገኘም። አዲስ መለያ ይፍጠሩ?',
      'dialog_cancel': 'ሰርዝ',
      'dialog_create': 'ፍጠር',
      'apple_signin_coming_soon': 'የApple መግቢያ በቅርብ ጊዜ ይመጣል።',
      'google_signin_failed': 'የGoogle መግቢያ አልተሳካም። እባክዎ እንደገና ይሞክሩ።',
      'apple_signin_failed': 'የApple መግቢያ አልተሳካም። እባክዎ እንደገና ይሞክሩ።',
      'sign_in_or_sign_up_with_google': 'በGoogle መለያ መግባት ወይም መመዝገብ',
      'sign_in_or_sign_up_with_apple': 'በApple መለያ መግባት ወይም መመዝገብ',
      'tv': 'ቲቪ',
      'radio': 'ሬዲዮ',
      'live_tv': 'ቀጥታ ቲቪ',
      'settings': 'ቅንብሮች',
      'appearance': 'አቀራረብ',
      'system': 'ሲስተም',
      'light': 'ብርሃን',
      'dark': 'ጨለማ',
      'language': 'ቋንቋ',
      'profile': 'መገለጫ',
      'profile_settings': 'የመገለጫ ቅንብሮች',
      'about': 'ስለ መተግበሪያው',
      'switch_language': 'ቋንቋ መቀየር',
      'english': 'እንግሊዝኛ',
      'amharic': 'አማርኛ',
      'oromo': 'ኦሮምኛ',
      // Settings page
      'security': 'ደህንነት',
      'active_sessions': 'ንቁ ክፍለጊዜዎች',
      'active_sessions_subtitle': 'ንቁ ክፍለጊዜዎችን ይመልከቱና ያቆጣጠሩ',
      'session_security': 'የክፍለጊዜ ደህንነት',
      'session_security_subtitle': 'የደህንነት ቅንብሮችን ያቀናብሩ',
      'notifications_section': 'ማሳወቂያዎች',
      'notification_inbox': 'የማሳወቂያ ሳጥን',
      'notification_inbox_subtitle': 'ማሳወቂያዎችን ይመልከቱ',
      // Channels page
      'offline_mode': 'ከመስመር ውጭ',
      'showing_cached': 'እስካትገናኙ ድረስ ቻናሎች ተቀምጠው ይታያሉ።',
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
      'all': 'ሁሉም',
      'menu': 'ምናሌ',
      'you_are_offline': 'ከመስመር ውጭ ነዎት',
      'some_actions_offline': 'እስካትገናኙ ድረስ አንዳንድ ተግባር አይሰራም።',
      'coming_soon': 'ለቅርብ ጊዜ',
      // Profile page
      'profile_details': 'የመገለጫ ዝርዝር',
      'first_name': 'የመጀመሪያ ስም',
      'last_name': 'የአባት ስም',
      'edit': 'አርትዕ',
      'cancel': 'ሰርዝ',
      'save_changes': 'ለውጦቹን አስቀምጥ',
      'sign_out': 'ዘግተው ውጡ',
      'danger_zone': 'አደገኛ ክፍል',
      'delete_account': 'መለያ ሰርዝ',
      'delete_account_title': 'መለያ ማጥፋት',
      'delete_account_body':
          'ይህ መለያዎን ያሰናክላል፣ የግል መረጃዎን ያስወግዳል እና ከሁሉም መሣሪያዎች ያወጣዎታል። አንዳንድ እንቅስቃሴ በስም አልተገናኘ መልክ ሊቀር ይችላል።',
      'delete_account_not_implemented':
          'የመለያ ማጥፋት ገና አልተተገበረም። እባክዎ ከድጋፍ ጋር ይገናኙ።',
      'delete_account_success': 'መለያዎ ተሰርዟል እና ከሁሉም መሣሪያዎች ወጥተዋል።',
      'delete_account_error': 'መለያዎን መሰረዝ አልተሳካም። እባክዎ ደግመው ይሞክሩ።',
      'profile_load_error': 'መገለጫ መጫን አልተሳካም',
      'profile_update_success': 'መገለጫ ተዘምኗል',
      'profile_update_error': 'መገለጫ ማዘመን አልተቻለም',
      // Email verification
      'email_not_verified_banner': 'ኢሜልዎ አልተረጋገጠም። አንዳንድ ተግባሮች ሊገደቡ ይችላሉ።',
      'verify_now': 'አሁን ተረጋግጥ',
      'verification_email_sent': 'የማረጋገጫ ኢሜል ተልኳል። እባክዎ መልዕክት ሳጥኑን ይመልከቱ።',
      'verification_email_failed': 'የማረጋገጫ ኢሜል መላክ አልተቻለም። እባክዎ እንደገና ይሞክሩ።',
      // Password & security
      'password_status_enabled': 'ፓስዎርድ፡ ተያይዟል',
      'password_status_not_set': 'ፓስዎርድ፡ አልተዘጋጀም',
      'password_manage_requires_verified_email':
          'ፓስዎርድዎን ለመቆጣጠር መጀመሪያ ኢሜልዎን ያረጋግጡ።',
      'enable_password': 'ፓስዎርድ አቅርብ',
      'disable_password': 'ፓስዎርድ አቋርጥ',
      'password_enabled_logged_out': 'ፓስዎርድ ተያይዟል። ከሁሉም መሣሪያዎች ወጥተዋል።',
      'password_disabled_logged_out': 'ፓስዎርድ ዘግቷል። ከሁሉም መሣሪያዎች ወጥተዋል።',
      // Forgot password
      'forgot_password': 'ፓስዎርድ ረስተዋል?',
      'password_reset_email_sent_generic':
          'ተረጋገጠ ኢሜል ያለው መለያ ካለ የመመለሻ አገናኝ ተልኳል።',
    };
    const om = {
      'home': 'Mana',
      'channels': 'Kanaalota',
      'logout': 'Baʼii',
      'welcome': 'Baga nagaan dhuftan',
      'for_you': 'Siif',
      'Shows': 'Sirkii',
      'Categories': 'Ramaddiiwwan',
      'trending': 'Sirna keessa jiran',
      'sports': 'Ispoortii',
      'kids': 'Daa’imman',
      'Shorts': 'Vidiyoo gabaabaa',
      'browse_channels': 'Kanaalota ilaali',
      'continue_watching': 'Itti fufi',
      'see_all': 'Hundaa ilaali',
      'trending_now': 'Amma keessa jiru',
      'new_releases': 'Gad dhiifama haaraa',
      'go_live': 'Gara kallattii seen',
      'play': 'Taphadhu',
      'live': 'Kallattiin',
      'now_playing': 'Amma taphachaa jiru',
      // Login page
      'welcome_back': 'Baga deebiʼan',
      'login_subtitle': 'Akaawuntii Google kee fayyadamuun seeni',
      'toggle_dark_mode': 'Haala dukkanaaʼaa baddaluu',
      'create_account': 'Akaawuntii uumi',
      'enter_valid_email': 'Imeelii sirrii galchi.',
      'login_failed': 'Seenuun hin milkoofne',
      'incorrect_email_password': 'Imeelii ykn jecha iccitii dogoggoraa.',
      'too_many_attempts':
          'Yeroo baayʼee yaaliin taasifameera. Daqiiqaa muraasa eegee deebiʼi.',
      'account_locked':
          'Sababa yaalii baayʼee irraa kaʼee akkaawuntiin yeroo muraasaaf cufame.',
      'generic_error': 'Rakkoon uumame. Mee as booddeetti irra deebiʼi yaali.',
      'email_or_username': 'Imeelii ykn maqaa fayyadamaa',
      'email_or_username_required':
          'Imeelii ykn maqaa fayyadamaa galchuu barbaachisa',
      'password_label': 'Jecha iccitii',
      'password_required': 'Jecha iccitii galchi',
      'sign_in': 'Seeni',
      'use_phone_coming_soon': 'Bilbila fayyadamuun (dhiyootti ni dhufa)',
      'choose_language': 'Afaan filadhu',
      'create_new_account_title': 'Akaawuntii haaraa uumi?',
      'create_new_account_body':
          'Akaawuntiin Google kanaaf hin jiru. Amma uftu?',
      'dialog_cancel': 'Haqi',
      'dialog_create': 'Uumi',
      'apple_signin_coming_soon': 'Seensa Apple dhiyootti ni dhufa.',
      'google_signin_failed': 'Seensi Google hin milkoofne. Mee deebiʼi yaali.',
      'apple_signin_failed': 'Seensi Apple hin milkoofne. Mee deebiʼi yaali.',
      'sign_in_or_sign_up_with_google':
          'Google fayyadamuun seeni yookaan galmaa’i',
      'sign_in_or_sign_up_with_apple':
          'Apple fayyadamuun seeni yookaan galmaa’i',
      'tv': 'TV',
      'radio': 'Raadiyoo',
      'live_tv': 'TV kallattiin',
      'settings': 'Kaaroorfama',
      'appearance': 'Ilaalcha',
      'system': 'Sirna',
      'light': 'Ifaa',
      'dark': 'Dukkana',
      'language': 'Afaan',
      'profile': 'Profaayilii',
      'profile_settings': 'Qindaa’ina Profaayilii',
      'about': 'Waan akeekuu',
      'switch_language': 'Afaan jijjiiri',
      'english': 'Afaan Ingiliffaa',
      'amharic': 'Afaan Amaaraa',
      'oromo': 'Afaan Oromoo',
      // Settings page
      'security': 'Nageenya',
      'active_sessions': 'Kallattiin jirus',
      'active_sessions_subtitle': 'Tartiiba tajaajilaa ilaali',
      'session_security': 'Nageenya tajaajilaa',
      'session_security_subtitle': 'Qindaa’ina nageenya',
      'notifications_section': 'Beeksisa',
      'notification_inbox': 'Sanduuqa beeksisaa',
      'notification_inbox_subtitle': 'Beeksisa ilaali',
      // Channels page
      'offline_mode': 'Al-internaatii',
      'showing_cached': 'Kanaalota kuufaman ni mul’atu.',
      'retry': 'Irra deebi’i',
      'loading': 'Fe’amaa jira…',
      'you_are_offline': 'Al internaatii jirtu',
      'some_actions_offline': 'Hojii muraasni interneetiin hin hojjatu.',
      'no_playlists': 'Tarree taphataa hin jiru',
      'no_videos': 'Vidiyoo hin jiru',
      'refresh_playlists': 'Taphattoota haaromsu',
      // Channel details modal
      'channel_details': 'Odeeffannoo kanaalaa',
      'info': 'Odeeffannoo',
      'close': 'Cufi',
      'tenant_label': 'Tajaajilaa',
      'id_slug': 'Id slug',
      'default_locale': 'Lakkoofsa durtii',
      'name_am': 'Maqaa Amaaraa',
      'name_en': 'Maqaa Ingiliffaa',
      'aliases': 'Maqaa bifa biraa',
      'youtube_handle': 'Handeela YouTube',
      'channel_handle': 'Handeela kanaalaa',
      'youtube_channel_id': 'Id YouTube',
      'resolved_channel_id': 'ID murtaa’e',
      'images': 'Suuraawwan',
      'sources': 'Maddawwan',
      'genres': 'Gosa',
      'language_label': 'Afaan',
      'country': 'Biyyaa',
      'tags': 'Mallattoo',
      'is_active': 'Jiru',
      'platforms': 'Pilaattifooma',
      'drm_required': 'DRM barbaachisa',
      'sort_order': 'Sirna lakkaa’insaa',
      'featured': 'Mul’ata addaa',
      'rights': 'Mirga',
      'audit': 'Odiitii',
      // Profile page
      'profile_details': 'Odeeffannoo profaayilii',
      'first_name': 'Maqaa jalqabaa',
      'last_name': 'Maqaa abbaa',
      'edit': 'Gulaali',
      'cancel': 'Haqi',
      'save_changes': 'Jijjiirama ol kaa’i',
      'sign_out': 'Bahuu',
      'danger_zone': 'Kutaa Halaakaa',
      'delete_account': 'Akkaawuntii haquu',
      'delete_account_title': 'Akkaawuntii haquu',
      'delete_account_body':
          'Kun akkaawuntii kee ni dhaamsa, odeeffannoo dhuunfaa irraa haqa, fi meeshaalee hunda irraa si baasaa. Sochii muraasni maqaa hin qabne taʼee ni hafu dandaʼa.',
      'delete_account_not_implemented': 'hojii irra hin oolle',
      'delete_account_success':
          'Akkaawuntiin kee haqame, meeshaalee hunda irraa baattee jirta.',
      'delete_account_error':
          'Akkaawuntii haquu hin dandeenye. Mee irra deebiʼi yaali.',
      'profile_load_error': 'Rakkoo fe’ii profaayilii',
      'profile_update_success': 'Profaayiliin haaromfame',
      'profile_update_error': 'Haaromsuu hin milkoofne',
      // Email verification
      'email_not_verified_banner':
          'Imeelli kee hin mirkanoofne. Amaloota muraasni ni daangeffamu.',
      'verify_now': 'Amma mirkaneessi',
      'verification_email_sent':
          'Imeeli mirkaneessuu ergameera. Sanduuqa galtee kee ilaali.',
      'verification_email_failed':
          'Imeeli mirkaneessuu ergu hin dandeenye. Mee irra deebiʼi yaali.',
      // Common UI extras
      'search': 'Barbaadi',
      'menu': 'Cuqaasaa',
      'coming_soon': 'Dhiyootti ni dhufa',
      'all': 'Hunduu',
      // Password & security
      'password_status_enabled': 'Jecha iccitii: hojiirra jira',
      'password_status_not_set': 'Jecha iccitii: hin jiru',
      'password_manage_requires_verified_email':
          'Jecha iccitii to’achuuf jalqaba imeelii kee mirkaneessi.',
      'enable_password': 'Jecha iccitii qindeessi',
      'disable_password': 'Jecha iccitii jalaa buusi',
      'password_enabled_logged_out':
          'Jecha iccitii qindeessite. Meeshaalee hunda irraa baattee jirta.',
      'password_disabled_logged_out':
          'Jecha iccitii jalaa buuste. Meeshaalee hunda irraa baattee jirta.',
      // Forgot password
      'forgot_password': 'Jecha iccitii dagatte?',
      'password_reset_email_sent_generic':
          'Akaawuntiin imeelii mirkanaaʼe qabu yoo jiraate, qunnamtiin haaromsuu ergameera.',
    };
    final dict = _lang == AppLanguage.en
        ? en
        : _lang == AppLanguage.am
            ? am
            : om;
    return dict[key] ?? key;
  }
}

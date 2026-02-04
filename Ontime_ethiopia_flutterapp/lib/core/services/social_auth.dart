import 'dart:io' show Platform;
import 'package:google_sign_in/google_sign_in.dart';

// Optionally provided via --dart-define=GOOGLE_OAUTH_WEB_CLIENT_ID=... when running the app
const String _envGoogleWebClientId =
    String.fromEnvironment('GOOGLE_OAUTH_WEB_CLIENT_ID', defaultValue: '');
// Optionally provided via --dart-define=GOOGLE_IOS_CLIENT_ID=... for iOS client id
const String _envGoogleIosClientId =
    String.fromEnvironment('GOOGLE_IOS_CLIENT_ID', defaultValue: '');

class SocialAuthResult {
  final String provider; // 'google' or 'apple'
  final String? idToken;
  final String? accessToken;
  final String? email;
  final String? displayName;

  SocialAuthResult({
    required this.provider,
    this.idToken,
    this.accessToken,
    this.email,
    this.displayName,
  });
}

class SocialAuthService {
  final String? serverClientId; // Required on Android to obtain idToken
  SocialAuthService({this.serverClientId});

  Future<void> _ensureGoogleInitialized() async {
    final String? serverId = Platform.isAndroid
        ? (serverClientId?.isNotEmpty == true
            ? serverClientId
            : (_envGoogleWebClientId.isNotEmpty ? _envGoogleWebClientId : null))
        : null;
    final String? clientId = Platform.isIOS
        ? (_envGoogleIosClientId.isNotEmpty ? _envGoogleIosClientId : null)
        : null;

    // google_sign_in v7 uses a singleton instance that must be initialized.
    await GoogleSignIn.instance.initialize(
      clientId: clientId,
      serverClientId: serverId,
    );
  }

  /// Sign out from the app session for GoogleSignIn so the account chooser is shown next time.
  Future<void> signOutGoogle() async {
    try {
      await _ensureGoogleInitialized();
      await GoogleSignIn.instance.signOut();
    } catch (_) {}
  }

  Future<SocialAuthResult> signInWithGoogle({bool signOutFirst = false}) async {
    if (signOutFirst) {
      try {
        await signOutGoogle();
      } catch (_) {}
    }

    await _ensureGoogleInitialized();

    // v7: authenticate triggers interactive sign-in.
    final account = await GoogleSignIn.instance.authenticate();
    final auth = account.authentication;
    final idToken = auth.idToken; // This is what backend verifies
    if (idToken == null || idToken.isEmpty) {
      // Some devices may require re-auth prompts
      throw Exception('Failed to obtain Google ID token');
    }
    return SocialAuthResult(
      provider: 'google',
      idToken: idToken,
      accessToken: null,
      email: account.email,
      displayName: account.displayName,
    );
  }

  Future<SocialAuthResult> signInWithApple() async {
    if (!Platform.isIOS) {
      throw UnsupportedError('Apple Sign In is only available on iOS');
    }
    // TODO: integrate sign_in_with_apple and request credentials
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return SocialAuthResult(provider: 'apple');
  }
}

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

  GoogleSignIn _buildGoogle()
    => GoogleSignIn(
      // On Android, provide the Web client ID via serverClientId to obtain an idToken
      serverClientId: Platform.isAndroid
          ? (serverClientId?.isNotEmpty == true
              ? serverClientId
              : (_envGoogleWebClientId.isNotEmpty ? _envGoogleWebClientId : null))
          : null,
      // On iOS, pass the iOS clientId
      clientId: Platform.isIOS
          ? (_envGoogleIosClientId.isNotEmpty ? _envGoogleIosClientId : null)
          : null,
      scopes: const <String>[
        'email',
        'openid',
        'profile',
      ],
    );

  /// Sign out from the app session for GoogleSignIn so the account chooser is shown next time.
  Future<void> signOutGoogle() async {
    final gs = _buildGoogle();
    try {
      await gs.signOut();
      // Disconnect revokes granted scopes from this app; optional but helps reset state
      await gs.disconnect();
    } catch (_) {}
  }

  Future<SocialAuthResult> signInWithGoogle({bool signOutFirst = false}) async {
    final googleSignIn = _buildGoogle();
    if (signOutFirst) {
      try {
        await googleSignIn.signOut();
        await googleSignIn.disconnect();
      } catch (_) {}
    }

    final account = await googleSignIn.signIn();
    if (account == null) {
      throw Exception('Google sign-in aborted');
    }
    final auth = await account.authentication;
    final idToken = auth.idToken; // This is what backend verifies
    if (idToken == null || idToken.isEmpty) {
      // Some devices may require re-auth prompts
      throw Exception('Failed to obtain Google ID token');
    }
    return SocialAuthResult(
      provider: 'google',
      idToken: idToken,
      accessToken: auth.accessToken,
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

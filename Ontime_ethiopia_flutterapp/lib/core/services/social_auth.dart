import 'dart:io' show Platform;

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
  const SocialAuthService();

  Future<SocialAuthResult> signInWithGoogle() async {
    // TODO: integrate google_sign_in and obtain server auth code / idToken
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return SocialAuthResult(provider: 'google');
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

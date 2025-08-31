class Session {
  final String sessionId;
  final String accessToken;
  final String refreshToken;
  final Map<String, dynamic>? userData;
  final DateTime? tokenExpiry;
  final String deviceId;
  final DateTime createdAt;
  
  Session({
    required this.sessionId,
    required this.accessToken,
    required this.refreshToken,
    this.userData,
    this.tokenExpiry,
    required this.deviceId,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();
  
  /// Create from JSON response
  factory Session.fromJson(Map<String, dynamic> json) {
    return Session(
      sessionId: json['session_id'] ?? '',
      accessToken: json['access_token'] ?? json['access'] ?? '',
      refreshToken: json['refresh_token'] ?? json['refresh'] ?? '',
      userData: json['user'],
      tokenExpiry: json['expires_in'] != null
          ? DateTime.now().add(Duration(seconds: json['expires_in']))
          : null,
      deviceId: json['device_id'] ?? '',
    );
  }
  
  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'session_id': sessionId,
      'access_token': accessToken,
      'refresh_token': refreshToken,
      'user': userData,
      'device_id': deviceId,
      'created_at': createdAt.toIso8601String(),
      if (tokenExpiry != null) 'token_expiry': tokenExpiry!.toIso8601String(),
    };
  }
  
  /// Check if token is expired
  bool get isExpired {
    if (tokenExpiry == null) return false;
    return DateTime.now().isAfter(tokenExpiry!);
  }
  
  /// Check if token needs refresh (5 minutes before expiry)
  bool get needsRefresh {
    if (tokenExpiry == null) return false;
    return DateTime.now().isAfter(
      tokenExpiry!.subtract(const Duration(minutes: 5)),
    );
  }
  
  /// Copy with updated values
  Session copyWith({
    String? sessionId,
    String? accessToken,
    String? refreshToken,
    Map<String, dynamic>? userData,
    DateTime? tokenExpiry,
    String? deviceId,
  }) {
    return Session(
      sessionId: sessionId ?? this.sessionId,
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      userData: userData ?? this.userData,
      tokenExpiry: tokenExpiry ?? this.tokenExpiry,
      deviceId: deviceId ?? this.deviceId,
      createdAt: createdAt,
    );
  }
}

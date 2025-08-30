# Part 11: Flutter Version Gate

## Overview

This guide implements version checking and update enforcement in Flutter, integrating with the backend Version Gate API from Part 7.

## 11.1 Version Models

```dart
// lib/core/models/version_model.dart
import 'package:flutter/foundation.dart';

enum UpdateType {
  none,
  optional,
  required,
  forced,
}

enum VersionStatus {
  current,
  updateAvailable,
  deprecated,
  unsupported,
}

class AppVersionModel {
  final String platform;
  final String version;
  final String buildNumber;
  final VersionStatus status;
  final UpdateType updateType;
  final DateTime? releaseDate;
  final String? updateUrl;
  final String? updateTitle;
  final String? updateMessage;
  final List<String> changelog;
  final Map<String, dynamic> features;
  
  AppVersionModel({
    required this.platform,
    required this.version,
    required this.buildNumber,
    required this.status,
    required this.updateType,
    this.releaseDate,
    this.updateUrl,
    this.updateTitle,
    this.updateMessage,
    this.changelog = const [],
    this.features = const {},
  });
  
  factory AppVersionModel.fromJson(Map<String, dynamic> json) {
    return AppVersionModel(
      platform: json['platform'],
      version: json['version'],
      buildNumber: json['build_number'],
      status: _parseVersionStatus(json['status']),
      updateType: _parseUpdateType(json['update_type']),
      releaseDate: json['release_date'] != null 
          ? DateTime.parse(json['release_date'])
          : null,
      updateUrl: json['update_url'],
      updateTitle: json['update_title'],
      updateMessage: json['update_message'],
      changelog: List<String>.from(json['changelog'] ?? []),
      features: json['features'] ?? {},
    );
  }
  
  static VersionStatus _parseVersionStatus(String status) {
    switch (status) {
      case 'current':
        return VersionStatus.current;
      case 'update_available':
        return VersionStatus.updateAvailable;
      case 'deprecated':
        return VersionStatus.deprecated;
      case 'unsupported':
        return VersionStatus.unsupported;
      default:
        return VersionStatus.current;
    }
  }
  
  static UpdateType _parseUpdateType(String type) {
    switch (type) {
      case 'optional':
        return UpdateType.optional;
      case 'required':
        return UpdateType.required;
      case 'forced':
        return UpdateType.forced;
      default:
        return UpdateType.none;
    }
  }
}

class FeatureFlagModel {
  final String name;
  final bool enabled;
  final String description;
  final Map<String, dynamic> config;
  final String? minVersion;
  final String? maxVersion;
  
  FeatureFlagModel({
    required this.name,
    required this.enabled,
    required this.description,
    this.config = const {},
    this.minVersion,
    this.maxVersion,
  });
  
  factory FeatureFlagModel.fromJson(Map<String, dynamic> json) {
    return FeatureFlagModel(
      name: json['name'],
      enabled: json['enabled'] ?? false,
      description: json['description'] ?? '',
      config: json['config'] ?? {},
      minVersion: json['min_version'],
      maxVersion: json['max_version'],
    );
  }
}

class VersionCheckResponse {
  final AppVersionModel currentVersion;
  final AppVersionModel? latestVersion;
  final List<FeatureFlagModel> features;
  final bool updateRequired;
  final UpdateType updateType;
  
  VersionCheckResponse({
    required this.currentVersion,
    this.latestVersion,
    this.features = const [],
    required this.updateRequired,
    required this.updateType,
  });
  
  factory VersionCheckResponse.fromJson(Map<String, dynamic> json) {
    return VersionCheckResponse(
      currentVersion: AppVersionModel.fromJson(json['current_version']),
      latestVersion: json['latest_version'] != null
          ? AppVersionModel.fromJson(json['latest_version'])
          : null,
      features: (json['features'] as List<dynamic>?)
              ?.map((f) => FeatureFlagModel.fromJson(f))
              .toList() ??
          [],
      updateRequired: json['update_required'] ?? false,
      updateType: AppVersionModel._parseUpdateType(
        json['update_type'] ?? 'none',
      ),
    );
  }
}
```

## 11.2 Version Service

```dart
// lib/core/services/version_service.dart
import 'dart:io';
import 'package:package_info_plus/package_info_plus.dart';
import '../api/api_client.dart';
import '../models/version_model.dart';
import '../models/api_response.dart';

class VersionService {
  static final ApiClient _client = ApiClient();
  static PackageInfo? _packageInfo;
  static VersionCheckResponse? _lastCheck;
  static DateTime? _lastCheckTime;
  
  // Cache duration for version check (30 minutes)
  static const Duration _cacheDuration = Duration(minutes: 30);
  
  /// Initialize package info
  static Future<void> initialize() async {
    _packageInfo = await PackageInfo.fromPlatform();
  }
  
  /// Get current app version
  static String get currentVersion {
    return _packageInfo?.version ?? '1.0.0';
  }
  
  /// Get current build number
  static String get currentBuildNumber {
    return _packageInfo?.buildNumber ?? '1';
  }
  
  /// Check version status with backend
  static Future<ApiResponse<VersionCheckResponse>> checkVersion({
    bool forceRefresh = false,
  }) async {
    // Use cached response if available and not forced
    if (!forceRefresh && 
        _lastCheck != null && 
        _lastCheckTime != null &&
        DateTime.now().difference(_lastCheckTime!) < _cacheDuration) {
      return ApiResponse.success(_lastCheck!);
    }
    
    try {
      final platform = Platform.isIOS ? 'ios' : 'android';
      
      final response = await _client.post(
        '/version/check',
        data: {
          'platform': platform,
          'version': currentVersion,
          'build_number': currentBuildNumber,
        },
      );
      
      final versionResponse = VersionCheckResponse.fromJson(response.data);
      
      // Cache the response
      _lastCheck = versionResponse;
      _lastCheckTime = DateTime.now();
      
      return ApiResponse.success(versionResponse);
    } catch (e) {
      return ApiResponse.error(e as ApiError);
    }
  }
  
  /// Get latest version info
  static Future<ApiResponse<AppVersionModel>> getLatestVersion() async {
    try {
      final platform = Platform.isIOS ? 'ios' : 'android';
      
      final response = await _client.get(
        '/version/latest',
        queryParameters: {'platform': platform},
      );
      
      final version = AppVersionModel.fromJson(response.data);
      return ApiResponse.success(version);
    } catch (e) {
      return ApiResponse.error(e as ApiError);
    }
  }
  
  /// Get feature flags
  static Future<ApiResponse<List<FeatureFlagModel>>> getFeatureFlags() async {
    try {
      final platform = Platform.isIOS ? 'ios' : 'android';
      
      final response = await _client.get(
        '/features',
        queryParameters: {
          'platform': platform,
          'version': currentVersion,
        },
      );
      
      final features = (response.data as List<dynamic>)
          .map((f) => FeatureFlagModel.fromJson(f))
          .toList();
      
      return ApiResponse.success(features);
    } catch (e) {
      return ApiResponse.error(e as ApiError);
    }
  }
  
  /// Check if a feature is enabled
  static bool isFeatureEnabled(String featureName) {
    if (_lastCheck == null) return false;
    
    final feature = _lastCheck!.features.firstWhere(
      (f) => f.name == featureName,
      orElse: () => FeatureFlagModel(
        name: featureName,
        enabled: false,
        description: '',
      ),
    );
    
    return feature.enabled;
  }
  
  /// Get feature configuration
  static Map<String, dynamic> getFeatureConfig(String featureName) {
    if (_lastCheck == null) return {};
    
    final feature = _lastCheck!.features.firstWhere(
      (f) => f.name == featureName,
      orElse: () => FeatureFlagModel(
        name: featureName,
        enabled: false,
        description: '',
        config: {},
      ),
    );
    
    return feature.config;
  }
}
```

## 11.3 Version Manager

```dart
// lib/core/managers/version_manager.dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/version_service.dart';
import '../models/version_model.dart';

class VersionManager extends ChangeNotifier {
  static final VersionManager _instance = VersionManager._internal();
  factory VersionManager() => _instance;
  VersionManager._internal();
  
  VersionCheckResponse? _versionInfo;
  bool _isChecking = false;
  String? _error;
  bool _updateDismissed = false;
  
  VersionCheckResponse? get versionInfo => _versionInfo;
  bool get isChecking => _isChecking;
  String? get error => _error;
  bool get hasUpdate => _versionInfo?.updateRequired ?? false;
  UpdateType get updateType => _versionInfo?.updateType ?? UpdateType.none;
  
  /// Initialize version manager
  Future<void> initialize() async {
    await VersionService.initialize();
    await checkVersion();
  }
  
  /// Check version status
  Future<void> checkVersion({bool forceRefresh = false}) async {
    _isChecking = true;
    _error = null;
    notifyListeners();
    
    final response = await VersionService.checkVersion(
      forceRefresh: forceRefresh,
    );
    
    _isChecking = false;
    
    if (response.success) {
      _versionInfo = response.data;
      _updateDismissed = false;
    } else {
      _error = response.error?.message;
    }
    
    notifyListeners();
  }
  
  /// Show update dialog
  void showUpdateDialog(BuildContext context) {
    if (_versionInfo == null || !hasUpdate || _updateDismissed) return;
    
    final latestVersion = _versionInfo!.latestVersion;
    if (latestVersion == null) return;
    
    showDialog(
      context: context,
      barrierDismissible: updateType != UpdateType.forced,
      builder: (context) => WillPopScope(
        onWillPop: () async => updateType != UpdateType.forced,
        child: AlertDialog(
          title: Text(latestVersion.updateTitle ?? 'Update Available'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  latestVersion.updateMessage ?? 
                  'A new version ${latestVersion.version} is available.',
                ),
                if (latestVersion.changelog.isNotEmpty) ...[
                  SizedBox(height: 16),
                  Text(
                    'What\'s New:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  ...latestVersion.changelog.map(
                    (item) => Padding(
                      padding: EdgeInsets.only(left: 8, bottom: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('• '),
                          Expanded(child: Text(item)),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: _buildDialogActions(context, latestVersion),
        ),
      ),
    );
  }
  
  List<Widget> _buildDialogActions(
    BuildContext context,
    AppVersionModel latestVersion,
  ) {
    final actions = <Widget>[];
    
    // Add dismiss button for optional updates
    if (updateType == UpdateType.optional) {
      actions.add(
        TextButton(
          onPressed: () {
            _updateDismissed = true;
            Navigator.of(context).pop();
          },
          child: Text('Later'),
        ),
      );
    }
    
    // Add skip button for required updates (not forced)
    if (updateType == UpdateType.required) {
      actions.add(
        TextButton(
          onPressed: () {
            _updateDismissed = true;
            Navigator.of(context).pop();
          },
          child: Text('Skip This Version'),
        ),
      );
    }
    
    // Add update button
    actions.add(
      ElevatedButton(
        onPressed: () => _openUpdateUrl(latestVersion.updateUrl),
        child: Text('Update Now'),
      ),
    );
    
    return actions;
  }
  
  /// Open update URL
  Future<void> _openUpdateUrl(String? url) async {
    if (url == null) return;
    
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
    }
  }
  
  /// Check if update should block app usage
  bool shouldBlockApp() {
    return updateType == UpdateType.forced && !_updateDismissed;
  }
  
  /// Check if a feature is enabled
  bool isFeatureEnabled(String featureName) {
    return VersionService.isFeatureEnabled(featureName);
  }
  
  /// Get feature configuration
  Map<String, dynamic> getFeatureConfig(String featureName) {
    return VersionService.getFeatureConfig(featureName);
  }
}
```

## 11.4 Version Gate Widget

```dart
// lib/core/widgets/version_gate.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../managers/version_manager.dart';
import '../models/version_model.dart';

class VersionGate extends StatefulWidget {
  final Widget child;
  final Widget? updateScreen;
  
  const VersionGate({
    Key? key,
    required this.child,
    this.updateScreen,
  }) : super(key: key);
  
  @override
  State<VersionGate> createState() => _VersionGateState();
}

class _VersionGateState extends State<VersionGate> {
  late VersionManager _versionManager;
  
  @override
  void initState() {
    super.initState();
    _versionManager = VersionManager();
    _checkVersion();
  }
  
  Future<void> _checkVersion() async {
    await _versionManager.initialize();
    
    // Show update dialog if needed
    if (mounted && _versionManager.hasUpdate) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _versionManager.showUpdateDialog(context);
      });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<VersionManager>.value(
      value: _versionManager,
      child: Consumer<VersionManager>(
        builder: (context, versionManager, _) {
          // Block app if forced update is required
          if (versionManager.shouldBlockApp()) {
            return widget.updateScreen ?? _buildForcedUpdateScreen();
          }
          
          return widget.child;
        },
      ),
    );
  }
  
  Widget _buildForcedUpdateScreen() {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.system_update,
                  size: 80,
                  color: Theme.of(context).primaryColor,
                ),
                SizedBox(height: 24),
                Text(
                  'Update Required',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                SizedBox(height: 16),
                Text(
                  'Please update to the latest version to continue using the app.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                SizedBox(height: 32),
                ElevatedButton(
                  onPressed: () {
                    final latestVersion = _versionManager.versionInfo?.latestVersion;
                    if (latestVersion?.updateUrl != null) {
                      _versionManager._openUpdateUrl(latestVersion!.updateUrl);
                    }
                  },
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                    child: Text('Update Now'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

## 11.5 Feature Flag Widget

```dart
// lib/core/widgets/feature_flag.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../managers/version_manager.dart';

class FeatureFlag extends StatelessWidget {
  final String featureName;
  final Widget child;
  final Widget? fallback;
  
  const FeatureFlag({
    Key? key,
    required this.featureName,
    required this.child,
    this.fallback,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    final versionManager = context.watch<VersionManager>();
    
    if (versionManager.isFeatureEnabled(featureName)) {
      return child;
    }
    
    return fallback ?? SizedBox.shrink();
  }
}

class FeatureFlagBuilder extends StatelessWidget {
  final String featureName;
  final Widget Function(BuildContext, bool, Map<String, dynamic>) builder;
  
  const FeatureFlagBuilder({
    Key? key,
    required this.featureName,
    required this.builder,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    final versionManager = context.watch<VersionManager>();
    
    final isEnabled = versionManager.isFeatureEnabled(featureName);
    final config = versionManager.getFeatureConfig(featureName);
    
    return builder(context, isEnabled, config);
  }
}
```

## 11.6 Usage Example

```dart
// lib/main.dart
import 'package:flutter/material.dart';
import 'core/widgets/version_gate.dart';
import 'core/widgets/feature_flag.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ontime App',
      home: VersionGate(
        child: HomeScreen(),
        updateScreen: CustomUpdateScreen(),
      ),
    );
  }
}

class HomeScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Home'),
        actions: [
          // Feature flag example
          FeatureFlag(
            featureName: 'new_profile',
            child: IconButton(
              icon: Icon(Icons.person),
              onPressed: () {
                // Navigate to new profile
              },
            ),
            fallback: IconButton(
              icon: Icon(Icons.account_circle),
              onPressed: () {
                // Navigate to old profile
              },
            ),
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Welcome to Ontime'),
            
            // Feature flag builder example
            FeatureFlagBuilder(
              featureName: 'premium_features',
              builder: (context, isEnabled, config) {
                if (isEnabled) {
                  final discount = config['discount'] ?? 0;
                  return Card(
                    child: ListTile(
                      title: Text('Premium Features'),
                      subtitle: Text('${discount}% off today!'),
                      trailing: Icon(Icons.star),
                      onTap: () {
                        // Show premium features
                      },
                    ),
                  );
                }
                return SizedBox.shrink();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class CustomUpdateScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).primaryColor,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.rocket_launch,
                size: 100,
                color: Colors.white,
              ),
              SizedBox(height: 32),
              Text(
                'Exciting Update!',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              // Custom update UI
            ],
          ),
        ),
      ),
    );
  }
}
```

## Testing

```dart
// test/version_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:your_app/core/models/version_model.dart';

void main() {
  group('Version Model Tests', () {
    test('Parse version status correctly', () {
      final json = {
        'platform': 'ios',
        'version': '1.2.3',
        'build_number': '123',
        'status': 'update_available',
        'update_type': 'optional',
      };
      
      final version = AppVersionModel.fromJson(json);
      
      expect(version.status, VersionStatus.updateAvailable);
      expect(version.updateType, UpdateType.optional);
    });
  });
}
```

## Dependencies

Add to `pubspec.yaml`:
```yaml
dependencies:
  package_info_plus: ^4.2.0
  url_launcher: ^6.1.14
```

## Security Notes

1. **Version Spoofing**: Validate version numbers server-side
2. **Update URLs**: Only use trusted app store URLs
3. **Feature Flags**: Cache with appropriate TTL
4. **Forced Updates**: Ensure graceful handling
5. **Network Failures**: Handle offline scenarios

## Next Steps

✅ Version checking integration
✅ Update enforcement
✅ Feature flag system
✅ Version gate UI
✅ Custom update screens

Continue to [Part 12: Flutter Auth Pages](./part12-flutter-pages.md)

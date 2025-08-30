# Part 12b: Flutter Auth Pages (Continued)

## 12.4 Registration Page

```dart
// lib/auth/pages/register_page.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../widgets/dynamic_form.dart';
import '../services/form_service.dart';
import '../models/form_schema_model.dart';
import '../widgets/otp_verification.dart';
import '../../core/managers/session_manager.dart';

class RegisterPage extends StatefulWidget {
  final VoidCallback? onSuccess;
  
  const RegisterPage({Key? key, this.onSuccess}) : super(key: key);
  
  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  FormSchemaModel? _formSchema;
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _error;
  int _currentStep = 0;
  Map<String, dynamic> _formData = {};
  
  @override
  void initState() {
    super.initState();
    _loadFormSchema();
  }
  
  Future<void> _loadFormSchema() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    
    final response = await FormService.getFormSchema('register');
    
    setState(() {
      _isLoading = false;
      if (response.success) {
        _formSchema = response.data;
      } else {
        _error = response.error?.message;
      }
    });
  }
  
  Future<void> _handleRegister(Map<String, dynamic> formData) async {
    setState(() {
      _isSubmitting = true;
      _error = null;
      _formData = {..._formData, ...formData};
    });
    
    // Check if OTP verification is needed
    if (_currentStep == 0 && _formSchema?.requiresOtp == true) {
      // Send OTP
      final otpResponse = await AuthService.sendOtp(
        email: _formData['email'],
        type: 'registration',
      );
      
      if (otpResponse.success) {
        setState(() {
          _currentStep = 1;
          _isSubmitting = false;
        });
        return;
      } else {
        setState(() {
          _error = otpResponse.error?.message;
          _isSubmitting = false;
        });
        return;
      }
    }
    
    // Complete registration
    final response = await AuthService.register(_formData);
    
    setState(() {
      _isSubmitting = false;
    });
    
    if (response.success) {
      // Update session
      final sessionManager = context.read<SessionManager>();
      await sessionManager.createSession(response.data!);
      
      // Navigate to onboarding or home
      if (widget.onSuccess != null) {
        widget.onSuccess!();
      } else {
        Navigator.of(context).pushReplacementNamed('/onboarding');
      }
    } else {
      setState(() {
        _error = response.error?.message;
      });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: () {
            if (_currentStep > 0) {
              setState(() {
                _currentStep--;
              });
            } else {
              Navigator.of(context).pop();
            }
          },
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildTitle(),
                  SizedBox(height: 32),
                  _buildProgress(),
                  SizedBox(height: 32),
                  _buildContent(),
                  SizedBox(height: 16),
                  _buildFooter(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildTitle() {
    final titles = [
      'Create Account',
      'Verify Email',
      'Complete Profile',
    ];
    
    return Column(
      children: [
        Text(
          titles[_currentStep.clamp(0, titles.length - 1)],
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        SizedBox(height: 8),
        Text(
          _getSubtitle(),
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Colors.grey[600],
              ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
  
  String _getSubtitle() {
    switch (_currentStep) {
      case 1:
        return 'We sent a verification code to ${_formData['email']}';
      case 2:
        return 'Tell us more about yourself';
      default:
        return 'Join thousands of users on Ontime';
    }
  }
  
  Widget _buildProgress() {
    if (_formSchema?.steps == null) return SizedBox.shrink();
    
    return Row(
      children: List.generate(
        _formSchema!.steps!,
        (index) => Expanded(
          child: Container(
            height: 4,
            margin: EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: index <= _currentStep
                  ? Theme.of(context).primaryColor
                  : Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildContent() {
    if (_isLoading) {
      return Center(child: CircularProgressIndicator());
    }
    
    if (_error != null && _formSchema == null) {
      return Column(
        children: [
          Icon(Icons.error_outline, size: 64, color: Colors.red),
          SizedBox(height: 16),
          Text(_error!),
          SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loadFormSchema,
            child: Text('Retry'),
          ),
        ],
      );
    }
    
    if (_formSchema == null) {
      return Text('Unable to load registration form');
    }
    
    return Column(
      children: [
        if (_error != null)
          Container(
            padding: EdgeInsets.all(12),
            margin: EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.red),
                SizedBox(width: 12),
                Expanded(child: Text(_error!)),
              ],
            ),
          ),
        
        if (_currentStep == 1)
          OtpVerificationWidget(
            email: _formData['email'],
            onVerify: (otp) {
              _formData['otp'] = otp;
              _handleRegister(_formData);
            },
            onResend: () async {
              await AuthService.sendOtp(
                email: _formData['email'],
                type: 'registration',
              );
            },
          )
        else
          DynamicForm(
            schema: _formSchema!,
            onSubmit: _handleRegister,
            isLoading: _isSubmitting,
            initialData: _formData,
          ),
      ],
    );
  }
  
  Widget _buildFooter() {
    if (_currentStep > 0) return SizedBox.shrink();
    
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('Already have an account? '),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Sign In'),
        ),
      ],
    );
  }
}
```

## 12.5 OTP Verification Widget

```dart
// lib/auth/widgets/otp_verification.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';

class OtpVerificationWidget extends StatefulWidget {
  final String email;
  final Function(String) onVerify;
  final VoidCallback onResend;
  
  const OtpVerificationWidget({
    Key? key,
    required this.email,
    required this.onVerify,
    required this.onResend,
  }) : super(key: key);
  
  @override
  State<OtpVerificationWidget> createState() => _OtpVerificationWidgetState();
}

class _OtpVerificationWidgetState extends State<OtpVerificationWidget> {
  final List<TextEditingController> _controllers = List.generate(
    6,
    (index) => TextEditingController(),
  );
  final List<FocusNode> _focusNodes = List.generate(
    6,
    (index) => FocusNode(),
  );
  
  int _resendTimer = 60;
  Timer? _timer;
  bool _isVerifying = false;
  
  @override
  void initState() {
    super.initState();
    _startResendTimer();
    _focusNodes[0].requestFocus();
  }
  
  @override
  void dispose() {
    _timer?.cancel();
    for (var controller in _controllers) {
      controller.dispose();
    }
    for (var node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }
  
  void _startResendTimer() {
    _resendTimer = 60;
    _timer?.cancel();
    _timer = Timer.periodic(Duration(seconds: 1), (timer) {
      if (_resendTimer > 0) {
        setState(() {
          _resendTimer--;
        });
      } else {
        timer.cancel();
      }
    });
  }
  
  String _getOtp() {
    return _controllers.map((c) => c.text).join();
  }
  
  void _handleVerify() {
    final otp = _getOtp();
    if (otp.length == 6) {
      setState(() {
        _isVerifying = true;
      });
      widget.onVerify(otp);
    }
  }
  
  void _handleResend() {
    widget.onResend();
    _startResendTimer();
    for (var controller in _controllers) {
      controller.clear();
    }
    _focusNodes[0].requestFocus();
  }
  
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          'Enter the 6-digit code sent to',
          style: TextStyle(fontSize: 16),
        ),
        SizedBox(height: 8),
        Text(
          widget.email,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: 32),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: List.generate(
            6,
            (index) => SizedBox(
              width: 45,
              height: 55,
              child: TextField(
                controller: _controllers[index],
                focusNode: _focusNodes[index],
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: 1,
                enabled: !_isVerifying,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  counterText: '',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
                onChanged: (value) {
                  if (value.isNotEmpty && index < 5) {
                    _focusNodes[index + 1].requestFocus();
                  }
                  if (index == 5 && value.isNotEmpty) {
                    _handleVerify();
                  }
                },
              ),
            ),
          ),
        ),
        SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isVerifying ? null : _handleVerify,
            child: _isVerifying
                ? CircularProgressIndicator(color: Colors.white)
                : Text('Verify'),
          ),
        ),
        SizedBox(height: 16),
        if (_resendTimer > 0)
          Text(
            'Resend code in $_resendTimer seconds',
            style: TextStyle(color: Colors.grey),
          )
        else
          TextButton(
            onPressed: _handleResend,
            child: Text('Resend Code'),
          ),
      ],
    );
  }
}
```

## 12.6 Auth Gate Widget

```dart
// lib/auth/widgets/auth_gate.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/managers/session_manager.dart';
import '../pages/login_page.dart';

class AuthGate extends StatelessWidget {
  final Widget authenticatedChild;
  final Widget? unauthenticatedChild;
  
  const AuthGate({
    Key? key,
    required this.authenticatedChild,
    this.unauthenticatedChild,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return Consumer<SessionManager>(
      builder: (context, sessionManager, _) {
        if (sessionManager.isAuthenticated) {
          return authenticatedChild;
        }
        
        return unauthenticatedChild ?? LoginPage(
          onSuccess: () {
            // Auth successful, will rebuild due to session change
          },
        );
      },
    );
  }
}
```

## 12.7 Complete App Integration

```dart
// lib/main.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/widgets/version_gate.dart';
import 'core/managers/session_manager.dart';
import 'auth/widgets/auth_gate.dart';
import 'auth/pages/login_page.dart';
import 'auth/pages/register_page.dart';
import 'home/pages/home_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize session manager
  final sessionManager = SessionManager();
  await sessionManager.initialize();
  
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: sessionManager),
      ],
      child: MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ontime Ethiopia',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          contentPadding: EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            padding: EdgeInsets.symmetric(
              horizontal: 32,
              vertical: 14,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
      home: VersionGate(
        child: SessionProvider(
          child: AuthGate(
            authenticatedChild: HomePage(),
          ),
        ),
      ),
      routes: {
        '/login': (context) => LoginPage(),
        '/register': (context) => RegisterPage(),
        '/home': (context) => HomePage(),
        '/onboarding': (context) => OnboardingPage(),
      },
    );
  }
}
```

## 12.8 Onboarding Page

```dart
// lib/onboarding/pages/onboarding_page.dart
import 'package:flutter/material.dart';

class OnboardingPage extends StatefulWidget {
  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  
  final List<OnboardingItem> _items = [
    OnboardingItem(
      image: 'assets/images/onboarding1.png',
      title: 'Welcome to Ontime',
      description: 'Your gateway to Ethiopian government services',
    ),
    OnboardingItem(
      image: 'assets/images/onboarding2.png',
      title: 'Secure Authentication',
      description: 'Multi-factor authentication keeps your data safe',
    ),
    OnboardingItem(
      image: 'assets/images/onboarding3.png',
      title: 'Get Started',
      description: 'Access services with a single tap',
    ),
  ];
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: TextButton(
                onPressed: _skip,
                child: Text('Skip'),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (index) {
                  setState(() {
                    _currentPage = index;
                  });
                },
                itemCount: _items.length,
                itemBuilder: (context, index) {
                  return _buildPage(_items[index]);
                },
              ),
            ),
            _buildIndicators(),
            SizedBox(height: 32),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _currentPage == _items.length - 1
                      ? _complete
                      : _next,
                  child: Text(
                    _currentPage == _items.length - 1
                        ? 'Get Started'
                        : 'Next',
                  ),
                ),
              ),
            ),
            SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
  
  Widget _buildPage(OnboardingItem item) {
    return Padding(
      padding: EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset(
            item.image,
            height: 250,
          ),
          SizedBox(height: 48),
          Text(
            item.title,
            style: Theme.of(context).textTheme.headlineMedium,
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 16),
          Text(
            item.description,
            style: Theme.of(context).textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
  
  Widget _buildIndicators() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        _items.length,
        (index) => Container(
          width: 8,
          height: 8,
          margin: EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _currentPage == index
                ? Theme.of(context).primaryColor
                : Colors.grey.shade300,
          ),
        ),
      ),
    );
  }
  
  void _next() {
    _pageController.nextPage(
      duration: Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }
  
  void _skip() {
    _complete();
  }
  
  void _complete() {
    Navigator.of(context).pushReplacementNamed('/home');
  }
}

class OnboardingItem {
  final String image;
  final String title;
  final String description;
  
  OnboardingItem({
    required this.image,
    required this.title,
    required this.description,
  });
}
```

## Testing

```dart
// test/auth_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:your_app/auth/services/auth_service.dart';

void main() {
  group('Auth Service Tests', () {
    test('Login returns auth response', () async {
      final response = await AuthService.login(
        email: 'test@example.com',
        password: 'password123',
      );
      
      expect(response.success, true);
      expect(response.data?.accessToken, isNotEmpty);
    });
  });
}
```

## Dependencies

Add to `pubspec.yaml`:
```yaml
dependencies:
  flutter:
    sdk: flutter
  provider: ^6.0.5
  dio: ^5.3.2
  flutter_secure_storage: ^9.0.0
  device_info_plus: ^9.1.0
  package_info_plus: ^4.2.0
  url_launcher: ^6.1.14
```

## Security Notes

1. **Token Storage**: Use secure storage for sensitive data
2. **Input Validation**: Validate all user inputs
3. **Session Management**: Handle session expiry gracefully
4. **Error Handling**: Never expose sensitive error details
5. **Social Auth**: Validate OAuth tokens server-side

## Summary

This completes the 12-part implementation guide series:

### Backend Parts (1-7)
✅ User model & session tracking
✅ JWT with token versioning  
✅ Refresh token rotation
✅ OTP authentication
✅ Social authentication
✅ Dynamic forms API
✅ Version gate API

### Flutter Parts (8-12)
✅ Session management
✅ HTTP interceptors
✅ Dynamic forms
✅ Version gate
✅ Auth pages

The complete system provides:
- Secure multi-provider authentication
- Session enforcement
- Token rotation
- Dynamic UI rendering
- Version control
- Feature flags

All components work together to create a robust, secure, and maintainable authentication system.

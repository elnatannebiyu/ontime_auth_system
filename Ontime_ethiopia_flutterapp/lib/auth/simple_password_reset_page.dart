import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import '../api_client.dart';
import '../core/localization/l10n.dart';

class SimplePasswordResetPage extends StatefulWidget {
  final String tenantId;
  final LocalizationController? localizationController;

  const SimplePasswordResetPage({
    super.key,
    required this.tenantId,
    this.localizationController,
  });

  @override
  State<SimplePasswordResetPage> createState() =>
      _SimplePasswordResetPageState();
}

class _SimplePasswordResetPageState extends State<SimplePasswordResetPage> {
  final _emailController = TextEditingController();
  final _otpController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final ApiClient _client = ApiClient();

  int _step = 1; // 1: email, 2: OTP, 3: new password
  bool _loading = false;
  String? _error;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  LocalizationController get _lc =>
      widget.localizationController ?? LocalizationController();
  String _t(String key) => _lc.t(key);

  @override
  void initState() {
    super.initState();
    _client.setTenant(widget.tenantId);
  }

  @override
  void dispose() {
    _emailController.dispose();
    _otpController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Enter a valid email address');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await _client.post('/password-reset/request/', data: {'email': email});

      if (mounted) {
        setState(() {
          _step = 2;
          _loading = false;
        });
      }
    } on DioException catch (e) {
      if (mounted) {
        String errorMsg = 'Failed to send code. Please try again.';

        // Handle rate limiting (429)
        if (e.response?.statusCode == 429) {
          errorMsg =
              'Too many requests. Please wait an hour before trying again.';
        }

        setState(() {
          _error = errorMsg;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to send code. Please try again.';
          _loading = false;
        });
      }
    }
  }

  Future<void> _verifyOtp() async {
    final otp = _otpController.text.trim();
    if (otp.length != 6) {
      setState(() => _error = 'Enter the 6-digit code from your email');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Verify OTP with backend before navigating to password step
      final res = await _client.post('/password-reset/verify/', data: {
        'token': otp,
      });

      final data = res.data as Map;
      final isValid = data['valid'] == true;

      if (isValid) {
        // OTP is valid, proceed to password step
        if (mounted) {
          setState(() {
            _step = 3;
            _loading = false;
          });
        }
      } else {
        // Should not happen if backend returns 400 for invalid
        if (mounted) {
          setState(() {
            _error = 'Invalid code. Please try again.';
            _loading = false;
          });
        }
      }
    } catch (e) {
      // Backend returned error (invalid or expired code)
      if (mounted) {
        setState(() {
          _error = 'Invalid or expired code. Please check and try again.';
          _loading = false;
        });
      }
    }
  }

  Future<void> _resetPassword() async {
    final password = _passwordController.text;
    final confirm = _confirmPasswordController.text;

    if (password.isEmpty) {
      setState(() => _error = 'Password is required');
      return;
    }

    if (password.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters');
      return;
    }

    if (password != confirm) {
      setState(() => _error = 'Passwords do not match');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await _client.post('/password-reset/confirm/', data: {
        'token': _otpController.text.trim(),
        'new_password': password,
      });

      if (mounted) {
        // Show success and navigate back
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Password reset successful! You can now login.'),
            backgroundColor: Colors.green,
          ),
        );

        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) Navigator.of(context).pop();
        });
      }
    } on DioException catch (e) {
      if (mounted) {
        String errorMsg = 'Invalid or expired code. Please try again.';

        // Parse password validation errors
        final data = e.response?.data;
        if (data is Map) {
          if (data['errors'] is List) {
            final errors = (data['errors'] as List).cast<String>();
            errorMsg = 'Password requirements:\n• ' + errors.join('\n• ');
          } else if (data['detail'] is String) {
            errorMsg = data['detail'] as String;
          }
        }

        setState(() {
          _error = errorMsg;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Invalid or expired code. Please try again.';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // Confirm before leaving if user is in the middle of the flow
        if (_step > 1 && !_loading) {
          final confirm = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(_t('cancel_reset_title')),
              content: Text(_t('cancel_reset_message')),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: Text(_t('stay')),
                ),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: Text(_t('leave')),
                ),
              ],
            ),
          );
          return confirm ?? false;
        }
        return true;
      },
      child: AnimatedBuilder(
        animation: _lc,
        builder: (context, _) => Scaffold(
          appBar: AppBar(
            title: Text(_t('reset_password')),
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Progress indicator
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildStepIndicator(1, _t('email_or_username')),
                      _buildStepLine(1),
                      _buildStepIndicator(2, _t('code_label')),
                      _buildStepLine(2),
                      _buildStepIndicator(3, _t('password_label')),
                    ],
                  ),
                  const SizedBox(height: 32),

                  // Step content
                  if (_step == 1) _buildEmailStep(),
                  if (_step == 2) _buildOtpStep(),
                  if (_step == 3) _buildPasswordStep(),

                  const SizedBox(height: 24),

                  // Error message
                  if (_error != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline, color: Colors.red.shade700),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(_error!,
                                style: TextStyle(color: Colors.red.shade700)),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStepIndicator(int stepNum, String label) {
    final isActive = _step >= stepNum;
    final isCurrent = _step == stepNum;

    return Flexible(
      child: Column(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive ? Colors.blue : Colors.grey.shade300,
              border:
                  isCurrent ? Border.all(color: Colors.blue, width: 2) : null,
            ),
            child: Center(
              child: Text(
                '$stepNum',
                style: TextStyle(
                  color: isActive ? Colors.white : Colors.grey.shade600,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              color: isActive ? Colors.blue : Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepLine(int stepNum) {
    final isActive = _step > stepNum;
    return Container(
      width: 40,
      height: 2,
      margin: const EdgeInsets.only(bottom: 16),
      color: isActive ? Colors.blue : Colors.grey.shade300,
    );
  }

  Widget _buildEmailStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _t('enter_email_address'),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          _t('send_code_instruction'),
          style: const TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          autofocus: true,
          decoration: InputDecoration(
            labelText: _t('email_or_username'),
            prefixIcon: const Icon(Icons.email),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton(
            onPressed: _loading ? null : _sendOtp,
            child: _loading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : Text(_t('send_code')),
          ),
        ),
      ],
    );
  }

  Widget _buildOtpStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _t('check_your_email'),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          _t('code_sent_to'),
          style: const TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 4),
        Text(
          _t('code_not_received'),
          style: const TextStyle(color: Colors.orange, fontSize: 12),
        ),
        const SizedBox(height: 4),
        Text(
          _t('check_spam_folder'),
          style: const TextStyle(
              color: Colors.blue, fontSize: 12, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _otpController,
          keyboardType: TextInputType.number,
          autofocus: true,
          maxLength: 6,
          textAlign: TextAlign.center,
          style: const TextStyle(
              fontSize: 24, letterSpacing: 8, fontWeight: FontWeight.bold),
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            labelText: _t('code_label'),
            border: const OutlineInputBorder(),
            counterText: '',
          ),
          onChanged: (value) {
            if (value.length == 6) {
              _verifyOtp();
            }
          },
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton(
            onPressed: _verifyOtp,
            child: Text(_t('continue_button')),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: TextButton(
            onPressed: () {
              setState(() {
                _step = 1;
                _otpController.clear();
                _error = null;
              });
            },
            child: Text(_t('try_again')),
          ),
        ),
      ],
    );
  }

  Widget _buildPasswordStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _t('create_new_password'),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          _t('password_requirements_hint'),
          style: const TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          autofocus: true,
          decoration: InputDecoration(
            labelText: _t('new_password'),
            prefixIcon: const Icon(Icons.lock),
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: Icon(
                  _obscurePassword ? Icons.visibility : Icons.visibility_off),
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _confirmPasswordController,
          obscureText: _obscureConfirm,
          decoration: InputDecoration(
            labelText: _t('confirm_password'),
            prefixIcon: const Icon(Icons.lock_outline),
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: Icon(
                  _obscureConfirm ? Icons.visibility : Icons.visibility_off),
              onPressed: () =>
                  setState(() => _obscureConfirm = !_obscureConfirm),
            ),
          ),
          onSubmitted: (_) => _resetPassword(),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton(
            onPressed: _loading ? null : _resetPassword,
            child: _loading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : Text(_t('reset_password_button')),
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'tenant_auth_client.dart';

class LoginPage extends StatefulWidget {
  final AuthApi api;
  final TokenStore tokenStore;
  final String tenantId;

  const LoginPage({
    super.key,
    required this.api,
    required this.tokenStore,
    required this.tenantId,
  });

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController(); // email-as-username supported by backend
  final _password = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final tenant = widget.tenantId;
      widget.api.setTenant(tenant);
      final tokens = await widget.api.login(
        tenantId: tenant,
        username: _username.text.trim(),
        password: _password.text,
      );
      await widget.tokenStore.setTokens(tokens.access, tokens.refresh);
      // Post-login guard: ensure user has access to current tenant
      try {
        await widget.api.me();
        if (!mounted) return;
        Navigator.of(context).pushNamedAndRemoveUntil('/home', (_) => false);
      } on DioException catch (e) {
        // Clear tokens and show backend detail
        await widget.tokenStore.clear();
        final data = e.response?.data;
        final detail = (data is Map && data['detail'] != null)
            ? '${data['detail']}'
            : e.message;
        setState(() {
          _error = detail ?? 'You do not have access to this tenant.';
        });
        return;
      }
    } on DioException catch (e) {
      final data = e.response?.data;
      final detail = (data is Map && data['detail'] != null) ? '${data['detail']}' : e.message;
      setState(() {
        _error = detail ?? 'Login failed';
      });
    } catch (e) {
      setState(() {
        _error = 'Something went wrong. Please try again.';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Sign in', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Text('Use your account to continue', style: TextStyle(color: Colors.grey[700])),
                  const SizedBox(height: 24),
                  if (_error != null)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.red.withOpacity(.25)),
                      ),
                      child: Text(_error!, style: const TextStyle(color: Colors.red)),
                    ),
                  Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _username,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Email or username',
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter your email/username' : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _password,
                          obscureText: _obscure,
                          onFieldSubmitted: (_) => _login(),
                          decoration: InputDecoration(
                            labelText: 'Password',
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                              onPressed: () => setState(() => _obscure = !_obscure),
                            ),
                          ),
                          validator: (v) => (v == null || v.isEmpty) ? 'Enter password' : null,
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: FilledButton(
                            onPressed: _loading ? null : _login,
                            child: _loading
                                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Text('Sign in'),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: () {
                            Navigator.of(context).pushReplacementNamed('/register');
                          },
                          child: const Text('Create an account'),
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
}

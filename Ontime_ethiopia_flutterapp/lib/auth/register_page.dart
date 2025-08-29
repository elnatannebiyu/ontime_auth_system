import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'tenant_auth_client.dart';

class RegisterPage extends StatefulWidget {
  final AuthApi api;
  final TokenStore tokenStore;
  final String tenantId;

  const RegisterPage({
    super.key,
    required this.api,
    required this.tokenStore,
    required this.tenantId,
  });

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure1 = true;
  bool _obscure2 = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final tenant = widget.tenantId;
      widget.api.setTenant(tenant);
      final tokens = await widget.api.register(
        tenantId: tenant,
        email: _email.text.trim(),
        password: _password.text,
      );
      await widget.tokenStore.setTokens(tokens.access, tokens.refresh);
      // Post-register guard: ensure membership/access to tenant
      try {
        await widget.api.me();
        if (!mounted) return;
        Navigator.of(context).pushNamedAndRemoveUntil('/home', (_) => false);
      } on DioException catch (e) {
        await widget.tokenStore.clear();
        final data = e.response?.data;
        String message = e.message ??
            'Registration succeeded, but access to this tenant is not permitted';
        if (data is Map && data['detail'] != null) {
          message = '${data['detail']}';
        }
        setState(() => _error = message);
        return;
      }
    } on DioException catch (e) {
      final data = e.response?.data;
      String message = e.message ?? 'Registration failed';
      if (data is Map && data['email'] != null) {
        message = (data['email'] as List?)?.join(', ') ?? '$message';
      } else if (data is Map && data['detail'] != null) {
        message = '${data['detail']}';
      }
      setState(() => _error = message);
    } catch (e) {
      setState(() => _error = 'Something went wrong. Please try again.');
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
                  const Text('Create account',
                      style:
                          TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Text('Join with your email and a strong password',
                      style: TextStyle(color: Colors.grey[700])),
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
                      child: Text(_error!,
                          style: const TextStyle(color: Colors.red)),
                    ),
                  Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _email,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Email',
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) {
                            final val = v?.trim() ?? '';
                            if (val.isEmpty) return 'Enter email';
                            final emailRe = RegExp(r'^.+@.+\..+$');
                            if (!emailRe.hasMatch(val))
                              return 'Enter a valid email';
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _password,
                          obscureText: _obscure1,
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            labelText: 'Password',
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              icon: Icon(_obscure1
                                  ? Icons.visibility
                                  : Icons.visibility_off),
                              onPressed: () =>
                                  setState(() => _obscure1 = !_obscure1),
                            ),
                          ),
                          validator: (v) {
                            final val = v ?? '';
                            if (val.isEmpty) return 'Enter password';
                            if (val.length < 8)
                              return 'Use at least 8 characters';
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _confirm,
                          obscureText: _obscure2,
                          onFieldSubmitted: (_) => _register(),
                          decoration: InputDecoration(
                            labelText: 'Confirm password',
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              icon: Icon(_obscure2
                                  ? Icons.visibility
                                  : Icons.visibility_off),
                              onPressed: () =>
                                  setState(() => _obscure2 = !_obscure2),
                            ),
                          ),
                          validator: (v) => (v ?? '') != _password.text
                              ? 'Passwords do not match'
                              : null,
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: FilledButton(
                            onPressed: _loading ? null : _register,
                            child: _loading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2))
                                : const Text('Create account'),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: () {
                            Navigator.of(context)
                                .pushReplacementNamed('/login');
                          },
                          child: const Text('Already have an account? Sign in'),
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

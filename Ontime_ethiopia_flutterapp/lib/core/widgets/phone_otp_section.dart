import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/phone_input_formatter.dart';

class PhoneOtpSection extends StatefulWidget {
  final void Function(String phone)? onSendOtp;
  final void Function(String phone, String code)? onVerifyOtp;
  final String defaultDialCode;

  const PhoneOtpSection({
    super.key,
    this.onSendOtp,
    this.onVerifyOtp,
    this.defaultDialCode = '+251',
  });

  @override
  State<PhoneOtpSection> createState() => _PhoneOtpSectionState();
}

class _PhoneOtpSectionState extends State<PhoneOtpSection> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  bool _sent = false;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _phone.text = widget.defaultDialCode;
  }

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() => _loading = true);
    try {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      widget.onSendOtp?.call(_phone.text.trim());
      if (mounted) setState(() => _sent = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _verify() async {
    setState(() => _loading = true);
    try {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      widget.onVerifyOtp?.call(_phone.text.trim(), _code.text.trim());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextFormField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
            SimplePhoneInputFormatter(defaultDialCode: widget.defaultDialCode),
          ],
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.phone_outlined),
            labelText: 'Phone number',
            border: OutlineInputBorder(),
            helperText: 'We will send a one-time code',
          ),
        ),
        const SizedBox(height: 12),
        if (!_sent)
          SizedBox(
            width: double.infinity,
            height: 44,
            child: FilledButton(
              onPressed: _loading ? null : _send,
              child: _loading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Send code'),
            ),
          ),
        if (_sent) ...[
          TextFormField(
            controller: _code,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.sms_outlined),
              labelText: 'Enter code',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: FilledButton(
              onPressed: _loading ? null : _verify,
              child: _loading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Verify and continue'),
            ),
          ),
        ],
      ],
    );
  }
}

import 'package:flutter/services.dart';

/// Very lightweight phone input formatter that:
/// - Forces leading +
/// - Keeps only digits after +
/// - Ensures default country code +251 when empty
class SimplePhoneInputFormatter extends TextInputFormatter {
  final String defaultDialCode;
  SimplePhoneInputFormatter({this.defaultDialCode = '+251'});

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    String text = newValue.text;
    if (text.isEmpty) {
      text = defaultDialCode;
    }
    if (!text.startsWith('+')) {
      text = '+${text.replaceAll('+', '')}';
    }
    // Keep + and digits only
    final cleaned = '+${text.replaceAll(RegExp(r'[^0-9+]'), '').replaceAll('+', '')}';
    return TextEditingValue(
      text: cleaned,
      selection: TextSelection.collapsed(offset: cleaned.length),
    );
  }
}

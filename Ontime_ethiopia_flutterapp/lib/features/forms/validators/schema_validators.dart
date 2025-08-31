import '../models/field_schema.dart';
import '../models/validation_rule.dart';

typedef ValidatorFn = String? Function(dynamic value, Map<String, dynamic> formValues);

class SchemaValidators {
  static ValidatorFn compose(FieldSchema field) {
    final rules = field.validations;
    return (dynamic value, Map<String, dynamic> formValues) {
      // required (field-level flag has priority)
      if (field.required) {
        final err = _required(value, field);
        if (err != null) return err;
      }

      for (final r in rules) {
        switch (r.type) {
          case ValidationType.required:
            final err = _required(value, field, message: r.message);
            if (err != null) return err;
            break;
          case ValidationType.minLength:
            if (value is String && r.intValue != null && value.length < r.intValue!) {
              return r.message ?? 'Must be at least ${r.intValue} characters';
            }
            break;
          case ValidationType.maxLength:
            if (value is String && r.intValue != null && value.length > r.intValue!) {
              return r.message ?? 'Must be at most ${r.intValue} characters';
            }
            break;
          case ValidationType.pattern:
            if (value is String && r.strValue != null) {
              final re = RegExp(r.strValue!);
              if (!re.hasMatch(value)) {
                return r.message ?? 'Invalid format';
              }
            }
            break;
          case ValidationType.email:
            if (value is String && value.isNotEmpty) {
              final re = RegExp(r'^.+@.+\..+$');
              if (!re.hasMatch(value)) return r.message ?? 'Invalid email address';
            }
            break;
          case ValidationType.phone:
            if (value is String && value.isNotEmpty) {
              final re = RegExp(r'^[0-9+\-()\s]{6,}$');
              if (!re.hasMatch(value)) return r.message ?? 'Invalid phone number';
            }
            break;
          case ValidationType.matchField:
            if (r.field != null) {
              final other = formValues[r.field];
              if (other != value) return r.message ?? 'Does not match ${r.field}';
            }
            break;
          case ValidationType.unique:
            // Backend should enforce; client-side skip or future async validation
            break;
          case ValidationType.strongPassword:
            if (value is String && value.isNotEmpty) {
              final hasUpper = value.contains(RegExp(r'[A-Z]'));
              final hasLower = value.contains(RegExp(r'[a-z]'));
              final hasDigit = value.contains(RegExp(r'[0-9]'));
              final hasSpecial = value.contains(RegExp(r'[!@#\$%^&*(),.?":{}|<>\-_=+\[\]\\/]'));
              if (!(hasUpper && hasLower && hasDigit && hasSpecial && value.length >= 8)) {
                return r.message ?? 'Use 8+ chars with upper, lower, digit, special';
              }
            }
            break;
        }
      }
      return null;
    };
  }

  static String? _required(dynamic value, FieldSchema field, {String? message}) {
    if (field.type == FieldType.checkbox) {
      final boolVal = value == true;
      if (!boolVal) return message ?? 'This field is required';
      return null;
    }
    if (value == null) return message ?? 'This field is required';
    if (value is String && value.trim().isEmpty) return message ?? 'This field is required';
    return null;
  }
}

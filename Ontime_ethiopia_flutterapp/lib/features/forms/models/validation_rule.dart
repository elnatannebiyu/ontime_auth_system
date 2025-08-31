import 'package:flutter/foundation.dart';

/// Validation rules supported by the backend dynamic forms API
/// (see authstack/accounts/form_schemas.py ValidationRule)
enum ValidationType {
  required,
  minLength,
  maxLength,
  pattern,
  email,
  phone,
  matchField,
  unique,
  strongPassword,
}

@immutable
class ValidationRuleModel {
  final ValidationType type;
  final String? message;
  final int? intValue; // for min/max length
  final String? strValue; // for pattern
  final String? field; // for matchField
  final String? model; // for unique
  final String? dbField; // for unique

  const ValidationRuleModel({
    required this.type,
    this.message,
    this.intValue,
    this.strValue,
    this.field,
    this.model,
    this.dbField,
  });

  factory ValidationRuleModel.fromMap(Map<String, dynamic> json) {
    final ruleRaw = (json['rule'] ?? json['type'] ?? '').toString();
    final type = _parseType(ruleRaw);
    return ValidationRuleModel(
      type: type,
      message: json['message'] as String?,
      intValue: (json['value'] is int)
          ? json['value'] as int
          : (json['value'] is String)
              ? int.tryParse(json['value'] as String)
              : null,
      strValue: json['value'] is String ? json['value'] as String : null,
      field: json['field'] as String?,
      model: json['model'] as String?,
      dbField: json['db_field'] as String? ?? json['field'] as String?,
    );
  }

  static ValidationType _parseType(String raw) {
    switch (raw) {
      case 'required':
        return ValidationType.required;
      case 'min_length':
      case 'minLength':
        return ValidationType.minLength;
      case 'max_length':
      case 'maxLength':
        return ValidationType.maxLength;
      case 'pattern':
        return ValidationType.pattern;
      case 'email':
        return ValidationType.email;
      case 'phone':
        return ValidationType.phone;
      case 'match_field':
      case 'matchField':
        return ValidationType.matchField;
      case 'unique':
        return ValidationType.unique;
      case 'strong_password':
      case 'strongPassword':
        return ValidationType.strongPassword;
      default:
        return ValidationType.required; // safe default
    }
  }
}

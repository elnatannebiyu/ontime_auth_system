import 'package:flutter/foundation.dart';

import 'validation_rule.dart';

enum FieldType {
  text,
  email,
  password,
  phone,
  otp,
  checkbox,
  select,
  radio,
  date,
  hidden,
}

@immutable
class FieldSchema {
  final String name;
  final FieldType type;
  final String? label;
  final String? placeholder;
  final dynamic defaultValue;
  final bool required;
  final bool disabled;
  final bool hidden;
  final List<ValidationRuleModel> validations;
  final List<dynamic>? options; // for select/radio; structure defined by backend
  final String? helpText;
  final String? icon;
  final String? dependsOn;
  final Map<String, dynamic>? conditionalLogic;

  const FieldSchema({
    required this.name,
    required this.type,
    this.label,
    this.placeholder,
    this.defaultValue,
    this.required = false,
    this.disabled = false,
    this.hidden = false,
    this.validations = const [],
    this.options,
    this.helpText,
    this.icon,
    this.dependsOn,
    this.conditionalLogic,
  });

  factory FieldSchema.fromMap(Map<String, dynamic> json) {
    return FieldSchema(
      name: json['name'] as String,
      type: _parseFieldType(json['type']?.toString() ?? 'text'),
      label: json['label'] as String?,
      placeholder: json['placeholder'] as String?,
      defaultValue: json['default_value'],
      required: (json['required'] as bool?) ?? false,
      disabled: (json['disabled'] as bool?) ?? false,
      hidden: (json['hidden'] as bool?) ?? false,
      validations: (json['validation'] ?? json['validations'] ?? [])
          .cast<dynamic>()
          .map<ValidationRuleModel>((e) =>
              ValidationRuleModel.fromMap((e as Map).cast<String, dynamic>()))
          .toList(growable: false),
      options: json['options'] as List<dynamic>?,
      helpText: json['help_text'] as String? ?? json['hint'] as String?,
      icon: json['icon']?.toString(),
      dependsOn: json['depends_on'] as String?,
      conditionalLogic:
          (json['conditional_logic'] as Map?)?.cast<String, dynamic>(),
    );
  }

  static FieldType _parseFieldType(String raw) {
    switch (raw) {
      case 'text':
        return FieldType.text;
      case 'email':
        return FieldType.email;
      case 'password':
        return FieldType.password;
      case 'phone':
        return FieldType.phone;
      case 'otp':
        return FieldType.otp;
      case 'checkbox':
        return FieldType.checkbox;
      case 'select':
        return FieldType.select;
      case 'radio':
        return FieldType.radio;
      case 'date':
        return FieldType.date;
      case 'hidden':
        return FieldType.hidden;
      default:
        return FieldType.text;
    }
  }
}

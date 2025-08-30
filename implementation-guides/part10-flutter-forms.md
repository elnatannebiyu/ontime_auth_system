# Part 10: Flutter Dynamic Forms

## Overview
Implement dynamic form rendering based on backend schemas with validation and submission.

## 10.1 Form Field Models

```dart
// lib/auth/models/form_field_model.dart
import 'package:flutter/material.dart';

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

enum ValidationType {
  required,
  email,
  minLength,
  maxLength,
  pattern,
  passwordStrength,
  match,
  phone,
  custom,
}

class FormFieldModel {
  final String name;
  final FieldType type;
  final String label;
  final String? placeholder;
  final dynamic defaultValue;
  final bool required;
  final bool disabled;
  final bool hidden;
  final List<ValidationRule> validations;
  final Map<String, dynamic>? options;
  final String? helpText;
  final IconData? icon;
  final String? dependsOn;
  final Map<String, dynamic>? conditionalLogic;
  
  FormFieldModel({
    required this.name,
    required this.type,
    required this.label,
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
  
  factory FormFieldModel.fromJson(Map<String, dynamic> json) {
    return FormFieldModel(
      name: json['name'],
      type: _parseFieldType(json['type']),
      label: json['label'],
      placeholder: json['placeholder'],
      defaultValue: json['default_value'],
      required: json['required'] ?? false,
      disabled: json['disabled'] ?? false,
      hidden: json['hidden'] ?? false,
      validations: _parseValidations(json['validations'] ?? []),
      options: json['options'],
      helpText: json['help_text'],
      icon: _parseIcon(json['icon']),
      dependsOn: json['depends_on'],
      conditionalLogic: json['conditional_logic'],
    );
  }
  
  static FieldType _parseFieldType(String type) {
    switch (type) {
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
  
  static List<ValidationRule> _parseValidations(List<dynamic> validations) {
    return validations.map((v) => ValidationRule.fromJson(v)).toList();
  }
  
  static IconData? _parseIcon(String? iconName) {
    if (iconName == null) return null;
    
    switch (iconName) {
      case 'email':
        return Icons.email;
      case 'lock':
        return Icons.lock;
      case 'person':
        return Icons.person;
      case 'phone':
        return Icons.phone;
      case 'calendar':
        return Icons.calendar_today;
      default:
        return Icons.text_fields;
    }
  }
}

class ValidationRule {
  final ValidationType type;
  final dynamic value;
  final String message;
  
  ValidationRule({
    required this.type,
    this.value,
    required this.message,
  });
  
  factory ValidationRule.fromJson(Map<String, dynamic> json) {
    return ValidationRule(
      type: _parseValidationType(json['type']),
      value: json['value'],
      message: json['message'],
    );
  }
  
  static ValidationType _parseValidationType(String type) {
    switch (type) {
      case 'required':
        return ValidationType.required;
      case 'email':
        return ValidationType.email;
      case 'min_length':
        return ValidationType.minLength;
      case 'max_length':
        return ValidationType.maxLength;
      case 'pattern':
        return ValidationType.pattern;
      case 'password_strength':
        return ValidationType.passwordStrength;
      case 'match':
        return ValidationType.match;
      case 'phone':
        return ValidationType.phone;
      default:
        return ValidationType.custom;
    }
  }
}
```

## 10.2 Form Schema Model

```dart
// lib/auth/models/form_schema_model.dart
class FormSchemaModel {
  final String formType;
  final String title;
  final String? subtitle;
  final List<FormFieldModel> fields;
  final List<FormAction> actions;
  final Map<String, dynamic>? metadata;
  final String? successMessage;
  final String? errorMessage;
  
  FormSchemaModel({
    required this.formType,
    required this.title,
    this.subtitle,
    required this.fields,
    required this.actions,
    this.metadata,
    this.successMessage,
    this.errorMessage,
  });
  
  factory FormSchemaModel.fromJson(Map<String, dynamic> json) {
    return FormSchemaModel(
      formType: json['form_type'],
      title: json['title'],
      subtitle: json['subtitle'],
      fields: (json['fields'] as List)
          .map((f) => FormFieldModel.fromJson(f))
          .toList(),
      actions: (json['actions'] as List)
          .map((a) => FormAction.fromJson(a))
          .toList(),
      metadata: json['metadata'],
      successMessage: json['success_message'],
      errorMessage: json['error_message'],
    );
  }
  
  FormFieldModel? getField(String name) {
    return fields.firstWhere(
      (f) => f.name == name,
      orElse: () => throw Exception('Field $name not found'),
    );
  }
}

class FormAction {
  final String type;
  final String label;
  final String? endpoint;
  final String? method;
  final bool isPrimary;
  final Map<String, dynamic>? metadata;
  
  FormAction({
    required this.type,
    required this.label,
    this.endpoint,
    this.method,
    this.isPrimary = false,
    this.metadata,
  });
  
  factory FormAction.fromJson(Map<String, dynamic> json) {
    return FormAction(
      type: json['type'],
      label: json['label'],
      endpoint: json['endpoint'],
      method: json['method'],
      isPrimary: json['is_primary'] ?? false,
      metadata: json['metadata'],
    );
  }
}
```

## 10.3 Dynamic Form Widget

```dart
// lib/auth/widgets/dynamic_form.dart
import 'package:flutter/material.dart';
import '../models/form_schema_model.dart';
import '../models/form_field_model.dart';
import 'form_field_widget.dart';
import '../services/form_validator.dart';

class DynamicForm extends StatefulWidget {
  final FormSchemaModel schema;
  final Function(Map<String, dynamic>) onSubmit;
  final Function(String field, dynamic value)? onFieldChange;
  final Map<String, dynamic>? initialValues;
  final bool isLoading;
  
  const DynamicForm({
    Key? key,
    required this.schema,
    required this.onSubmit,
    this.onFieldChange,
    this.initialValues,
    this.isLoading = false,
  }) : super(key: key);
  
  @override
  State<DynamicForm> createState() => _DynamicFormState();
}

class _DynamicFormState extends State<DynamicForm> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, dynamic> _formData = {};
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, String> _fieldErrors = {};
  final FormValidator _validator = FormValidator();
  
  @override
  void initState() {
    super.initState();
    _initializeForm();
  }
  
  void _initializeForm() {
    for (final field in widget.schema.fields) {
      // Set initial value
      if (widget.initialValues != null && 
          widget.initialValues!.containsKey(field.name)) {
        _formData[field.name] = widget.initialValues![field.name];
      } else if (field.defaultValue != null) {
        _formData[field.name] = field.defaultValue;
      }
      
      // Create controller for text fields
      if (_isTextField(field.type)) {
        _controllers[field.name] = TextEditingController(
          text: _formData[field.name]?.toString() ?? '',
        );
      }
    }
  }
  
  bool _isTextField(FieldType type) {
    return type == FieldType.text ||
           type == FieldType.email ||
           type == FieldType.password ||
           type == FieldType.phone ||
           type == FieldType.otp;
  }
  
  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Title
          if (widget.schema.title.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Text(
                widget.schema.title,
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
            ),
          
          // Subtitle
          if (widget.schema.subtitle != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 24.0),
              child: Text(
                widget.schema.subtitle!,
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ),
          
          // Fields
          ...widget.schema.fields
              .where((field) => !field.hidden && _shouldShowField(field))
              .map((field) => Padding(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: FormFieldWidget(
                      field: field,
                      value: _formData[field.name],
                      controller: _controllers[field.name],
                      error: _fieldErrors[field.name],
                      onChanged: (value) => _onFieldChanged(field.name, value),
                      validator: (value) => _validateField(field, value),
                    ),
                  )),
          
          // Actions
          const SizedBox(height: 24),
          ...widget.schema.actions.map((action) => Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: _buildActionButton(action),
              )),
        ],
      ),
    );
  }
  
  Widget _buildActionButton(FormAction action) {
    final isPrimary = action.isPrimary;
    
    return ElevatedButton(
      onPressed: widget.isLoading ? null : () => _handleAction(action),
      style: isPrimary
          ? ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            )
          : ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              foregroundColor: Theme.of(context).primaryColor,
              elevation: 0,
              minimumSize: const Size.fromHeight(48),
            ),
      child: widget.isLoading && isPrimary
          ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(action.label),
    );
  }
  
  void _handleAction(FormAction action) {
    if (action.type == 'submit') {
      _submitForm();
    } else if (action.type == 'cancel') {
      Navigator.of(context).pop();
    } else if (action.type == 'navigate') {
      Navigator.of(context).pushNamed(action.metadata?['route'] ?? '/');
    }
  }
  
  void _submitForm() {
    // Clear previous errors
    setState(() {
      _fieldErrors.clear();
    });
    
    // Validate form
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();
      
      // Submit form data
      widget.onSubmit(_formData);
    }
  }
  
  void _onFieldChanged(String fieldName, dynamic value) {
    setState(() {
      _formData[fieldName] = value;
      _fieldErrors.remove(fieldName);
    });
    
    // Notify parent
    widget.onFieldChange?.call(fieldName, value);
    
    // Check dependent fields
    _updateDependentFields(fieldName);
  }
  
  String? _validateField(FormFieldModel field, dynamic value) {
    for (final rule in field.validations) {
      final error = _validator.validate(rule, value, _formData);
      if (error != null) {
        return error;
      }
    }
    return null;
  }
  
  bool _shouldShowField(FormFieldModel field) {
    if (field.dependsOn == null) return true;
    
    final dependentValue = _formData[field.dependsOn];
    if (field.conditionalLogic != null) {
      final condition = field.conditionalLogic!['condition'];
      final expectedValue = field.conditionalLogic!['value'];
      
      switch (condition) {
        case 'equals':
          return dependentValue == expectedValue;
        case 'not_equals':
          return dependentValue != expectedValue;
        case 'contains':
          return dependentValue?.toString().contains(expectedValue) ?? false;
        default:
          return true;
      }
    }
    
    return dependentValue != null;
  }
  
  void _updateDependentFields(String fieldName) {
    setState(() {
      // Trigger rebuild to show/hide dependent fields
    });
  }
}
```

## 10.4 Form Field Widget (See Part 10b)

## 10.5 Form Validator Service (See Part 10b)

## 10.6 Form Service (See Part 10b)

## 10.7 Usage Example (See Part 10b)

Continue to [Part 10b: Flutter Dynamic Forms (continued)](./part10b-flutter-forms-continued.md)

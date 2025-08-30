# Part 10b: Flutter Dynamic Forms (Continued)

## 10.4 Form Field Widget

```dart
// lib/auth/widgets/form_field_widget.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/form_field_model.dart';

class FormFieldWidget extends StatelessWidget {
  final FormFieldModel field;
  final dynamic value;
  final TextEditingController? controller;
  final String? error;
  final Function(dynamic) onChanged;
  final String? Function(dynamic)? validator;
  
  const FormFieldWidget({
    Key? key,
    required this.field,
    this.value,
    this.controller,
    this.error,
    required this.onChanged,
    this.validator,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    switch (field.type) {
      case FieldType.text:
      case FieldType.email:
      case FieldType.password:
      case FieldType.phone:
      case FieldType.otp:
        return _buildTextField(context);
      case FieldType.checkbox:
        return _buildCheckbox(context);
      case FieldType.select:
        return _buildDropdown(context);
      case FieldType.radio:
        return _buildRadioGroup(context);
      case FieldType.date:
        return _buildDatePicker(context);
      case FieldType.hidden:
        return const SizedBox.shrink();
    }
  }
  
  Widget _buildTextField(BuildContext context) {
    return TextFormField(
      controller: controller,
      enabled: !field.disabled,
      obscureText: field.type == FieldType.password,
      keyboardType: _getKeyboardType(),
      inputFormatters: _getInputFormatters(),
      decoration: InputDecoration(
        labelText: field.label,
        hintText: field.placeholder,
        prefixIcon: field.icon != null ? Icon(field.icon) : null,
        helperText: field.helpText,
        errorText: error,
        suffixIcon: field.type == FieldType.password
            ? IconButton(
                icon: Icon(Icons.visibility),
                onPressed: () {
                  // Toggle password visibility
                },
              )
            : null,
      ),
      validator: validator,
      onChanged: onChanged,
      autofillHints: _getAutofillHints(),
    );
  }
  
  Widget _buildCheckbox(BuildContext context) {
    return CheckboxListTile(
      title: Text(field.label),
      subtitle: field.helpText != null ? Text(field.helpText!) : null,
      value: value ?? false,
      onChanged: field.disabled ? null : onChanged,
      controlAffinity: ListTileControlAffinity.leading,
    );
  }
  
  Widget _buildDropdown(BuildContext context) {
    final items = field.options?['items'] as List<dynamic>? ?? [];
    
    return DropdownButtonFormField<String>(
      value: value,
      decoration: InputDecoration(
        labelText: field.label,
        hintText: field.placeholder,
        prefixIcon: field.icon != null ? Icon(field.icon) : null,
        helperText: field.helpText,
        errorText: error,
      ),
      items: items.map((item) {
        final itemValue = item is Map ? item['value'] : item;
        final itemLabel = item is Map ? item['label'] : item;
        
        return DropdownMenuItem<String>(
          value: itemValue.toString(),
          child: Text(itemLabel.toString()),
        );
      }).toList(),
      onChanged: field.disabled ? null : onChanged,
      validator: validator,
    );
  }
  
  Widget _buildRadioGroup(BuildContext context) {
    final items = field.options?['items'] as List<dynamic>? ?? [];
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          field.label,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        if (field.helpText != null)
          Text(
            field.helpText!,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ...items.map((item) {
          final itemValue = item is Map ? item['value'] : item;
          final itemLabel = item is Map ? item['label'] : item;
          
          return RadioListTile<String>(
            title: Text(itemLabel.toString()),
            value: itemValue.toString(),
            groupValue: value?.toString(),
            onChanged: field.disabled ? null : onChanged,
          );
        }),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(left: 12.0, top: 8.0),
            child: Text(
              error!,
              style: TextStyle(
                color: Theme.of(context).errorColor,
                fontSize: 12,
              ),
            ),
          ),
      ],
    );
  }
  
  Widget _buildDatePicker(BuildContext context) {
    return InkWell(
      onTap: field.disabled
          ? null
          : () async {
              final date = await showDatePicker(
                context: context,
                initialDate: value ?? DateTime.now(),
                firstDate: DateTime(1900),
                lastDate: DateTime(2100),
              );
              if (date != null) {
                onChanged(date);
              }
            },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: field.label,
          hintText: field.placeholder,
          prefixIcon: field.icon != null ? Icon(field.icon) : null,
          helperText: field.helpText,
          errorText: error,
        ),
        child: Text(
          value != null
              ? '${value.day}/${value.month}/${value.year}'
              : field.placeholder ?? 'Select date',
        ),
      ),
    );
  }
  
  TextInputType _getKeyboardType() {
    switch (field.type) {
      case FieldType.email:
        return TextInputType.emailAddress;
      case FieldType.phone:
        return TextInputType.phone;
      case FieldType.otp:
        return TextInputType.number;
      default:
        return TextInputType.text;
    }
  }
  
  List<TextInputFormatter> _getInputFormatters() {
    switch (field.type) {
      case FieldType.phone:
        return [FilteringTextInputFormatter.digitsOnly];
      case FieldType.otp:
        return [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(6),
        ];
      default:
        return [];
    }
  }
  
  List<String> _getAutofillHints() {
    switch (field.type) {
      case FieldType.email:
        return [AutofillHints.email];
      case FieldType.password:
        return [AutofillHints.password];
      case FieldType.phone:
        return [AutofillHints.telephoneNumber];
      default:
        return [];
    }
  }
}
```

## 10.5 Form Validator Service

```dart
// lib/auth/services/form_validator.dart
import '../models/form_field_model.dart';

class FormValidator {
  String? validate(
    ValidationRule rule,
    dynamic value,
    Map<String, dynamic> formData,
  ) {
    switch (rule.type) {
      case ValidationType.required:
        return _validateRequired(value, rule.message);
        
      case ValidationType.email:
        return _validateEmail(value, rule.message);
        
      case ValidationType.minLength:
        return _validateMinLength(value, rule.value, rule.message);
        
      case ValidationType.maxLength:
        return _validateMaxLength(value, rule.value, rule.message);
        
      case ValidationType.pattern:
        return _validatePattern(value, rule.value, rule.message);
        
      case ValidationType.passwordStrength:
        return _validatePasswordStrength(value, rule.value, rule.message);
        
      case ValidationType.match:
        return _validateMatch(value, formData[rule.value], rule.message);
        
      case ValidationType.phone:
        return _validatePhone(value, rule.message);
        
      case ValidationType.custom:
        // Custom validation logic
        return null;
    }
  }
  
  String? _validateRequired(dynamic value, String message) {
    if (value == null || value.toString().isEmpty) {
      return message;
    }
    return null;
  }
  
  String? _validateEmail(dynamic value, String message) {
    if (value == null || value.toString().isEmpty) return null;
    
    final emailRegex = RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    );
    
    if (!emailRegex.hasMatch(value.toString())) {
      return message;
    }
    return null;
  }
  
  String? _validateMinLength(dynamic value, dynamic minLength, String message) {
    if (value == null) return null;
    
    if (value.toString().length < (minLength as int)) {
      return message;
    }
    return null;
  }
  
  String? _validateMaxLength(dynamic value, dynamic maxLength, String message) {
    if (value == null) return null;
    
    if (value.toString().length > (maxLength as int)) {
      return message;
    }
    return null;
  }
  
  String? _validatePattern(dynamic value, dynamic pattern, String message) {
    if (value == null || value.toString().isEmpty) return null;
    
    final regex = RegExp(pattern.toString());
    if (!regex.hasMatch(value.toString())) {
      return message;
    }
    return null;
  }
  
  String? _validatePasswordStrength(dynamic value, dynamic strength, String message) {
    if (value == null || value.toString().isEmpty) return null;
    
    final password = value.toString();
    int score = 0;
    
    // Check length
    if (password.length >= 8) score++;
    if (password.length >= 12) score++;
    
    // Check for uppercase
    if (password.contains(RegExp(r'[A-Z]'))) score++;
    
    // Check for lowercase
    if (password.contains(RegExp(r'[a-z]'))) score++;
    
    // Check for numbers
    if (password.contains(RegExp(r'[0-9]'))) score++;
    
    // Check for special characters
    if (password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'))) score++;
    
    final requiredStrength = strength ?? 3;
    if (score < requiredStrength) {
      return message;
    }
    return null;
  }
  
  String? _validateMatch(dynamic value, dynamic matchValue, String message) {
    if (value != matchValue) {
      return message;
    }
    return null;
  }
  
  String? _validatePhone(dynamic value, String message) {
    if (value == null || value.toString().isEmpty) return null;
    
    // Basic phone validation (adjust regex for specific formats)
    final phoneRegex = RegExp(r'^\+?[\d\s-()]+$');
    if (!phoneRegex.hasMatch(value.toString()) || 
        value.toString().length < 10) {
      return message;
    }
    return null;
  }
}
```

## 10.6 Form Service

```dart
// lib/auth/services/form_service.dart
import '../api/api_client.dart';
import '../models/form_schema_model.dart';
import '../models/api_response.dart';

class FormService {
  static final ApiClient _client = ApiClient();
  
  /// Get form schema
  static Future<ApiResponse<FormSchemaModel>> getFormSchema(
    String formType,
  ) async {
    try {
      final response = await _client.get(
        '/forms/schema/$formType',
      );
      
      final schema = FormSchemaModel.fromJson(response.data);
      return ApiResponse.success(schema);
    } catch (e) {
      return ApiResponse.error(e as ApiError);
    }
  }
  
  /// Validate field
  static Future<ApiResponse<Map<String, dynamic>>> validateField({
    required String formType,
    required String fieldName,
    required dynamic value,
  }) async {
    try {
      final response = await _client.post(
        '/forms/validate-field',
        data: {
          'form_type': formType,
          'field_name': fieldName,
          'value': value,
        },
      );
      
      return ApiResponse.success(response.data);
    } catch (e) {
      return ApiResponse.error(e as ApiError);
    }
  }
  
  /// Submit form
  static Future<ApiResponse<Map<String, dynamic>>> submitForm({
    required String formType,
    required Map<String, dynamic> data,
  }) async {
    try {
      final response = await _client.post(
        '/forms/submit',
        data: {
          'form_type': formType,
          'data': data,
        },
      );
      
      return ApiResponse.success(response.data);
    } catch (e) {
      return ApiResponse.error(e as ApiError);
    }
  }
}
```

## 10.7 Usage Example

```dart
// lib/auth/screens/dynamic_auth_screen.dart
import 'package:flutter/material.dart';
import '../widgets/dynamic_form.dart';
import '../services/form_service.dart';
import '../models/form_schema_model.dart';

class DynamicAuthScreen extends StatefulWidget {
  final String formType;
  
  const DynamicAuthScreen({
    Key? key,
    required this.formType,
  }) : super(key: key);
  
  @override
  State<DynamicAuthScreen> createState() => _DynamicAuthScreenState();
}

class _DynamicAuthScreenState extends State<DynamicAuthScreen> {
  FormSchemaModel? _schema;
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _error;
  
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
    
    final response = await FormService.getFormSchema(widget.formType);
    
    setState(() {
      _isLoading = false;
      if (response.success) {
        _schema = response.data;
      } else {
        _error = response.error?.message;
      }
    });
  }
  
  Future<void> _handleSubmit(Map<String, dynamic> data) async {
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    
    final response = await FormService.submitForm(
      formType: widget.formType,
      data: data,
    );
    
    setState(() {
      _isSubmitting = false;
    });
    
    if (response.success) {
      // Handle success
      _showSuccessDialog();
    } else {
      setState(() {
        _error = response.error?.message;
      });
    }
  }
  
  void _showSuccessDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Success'),
        content: Text(_schema?.successMessage ?? 'Form submitted successfully'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop(true);
            },
            child: Text('OK'),
          ),
        ],
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_schema?.title ?? 'Loading...'),
      ),
      body: SafeArea(
        child: _buildBody(),
      ),
    );
  }
  
  Widget _buildBody() {
    if (_isLoading) {
      return Center(child: CircularProgressIndicator());
    }
    
    if (_error != null && _schema == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
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
        ),
      );
    }
    
    if (_schema == null) {
      return Center(child: Text('No form schema available'));
    }
    
    return SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: Column(
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
          
          DynamicForm(
            schema: _schema!,
            onSubmit: _handleSubmit,
            isLoading: _isSubmitting,
            onFieldChange: (field, value) {
              // Optional: Handle field changes
              print('Field $field changed to $value');
            },
          ),
        ],
      ),
    );
  }
}
```

## Testing

```dart
// test/dynamic_form_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:your_app/auth/models/form_field_model.dart';
import 'package:your_app/auth/services/form_validator.dart';

void main() {
  group('Form Validator Tests', () {
    final validator = FormValidator();
    
    test('Required validation', () {
      final rule = ValidationRule(
        type: ValidationType.required,
        message: 'Field is required',
      );
      
      expect(validator.validate(rule, '', {}), 'Field is required');
      expect(validator.validate(rule, null, {}), 'Field is required');
      expect(validator.validate(rule, 'value', {}), null);
    });
    
    test('Email validation', () {
      final rule = ValidationRule(
        type: ValidationType.email,
        message: 'Invalid email',
      );
      
      expect(validator.validate(rule, 'invalid', {}), 'Invalid email');
      expect(validator.validate(rule, 'test@example.com', {}), null);
    });
    
    test('Password strength validation', () {
      final rule = ValidationRule(
        type: ValidationType.passwordStrength,
        value: 4,
        message: 'Password too weak',
      );
      
      expect(validator.validate(rule, 'weak', {}), 'Password too weak');
      expect(validator.validate(rule, 'Strong123!', {}), null);
    });
  });
}
```

## Security Notes

1. **Input Sanitization**: Always sanitize form inputs
2. **Field Validation**: Server-side validation is mandatory
3. **Rate Limiting**: Limit form submission attempts
4. **CSRF Protection**: Include CSRF tokens in forms
5. **Sensitive Data**: Never log passwords or sensitive fields

## Next Steps

✅ Dynamic form field models
✅ Form schema parsing
✅ Field rendering widgets
✅ Form validation service
✅ Form submission handling

Continue to [Part 11: Flutter Version Gate](./part11-flutter-version.md)

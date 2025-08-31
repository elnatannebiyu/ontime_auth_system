import 'package:dio/dio.dart';

import '../../../api_client.dart';
import '../models/form_schema.dart';

class FormService {
  FormService._();
  static final FormService _instance = FormService._();
  factory FormService() => _instance;

  final _client = ApiClient();

  Future<FormSchema> fetchSchema({required String action, Map<String, dynamic>? context, String? locale, String? theme}) async {
    final query = {
      'action': action,
      if (locale != null) 'locale': locale,
      if (theme != null) 'theme': theme,
      if (context != null) 'context': context, // will be serialized by dio
    };
    final res = await _client.get<Map<String, dynamic>>('/forms/schema/', queryParameters: query);
    final data = res.data ?? <String, dynamic>{};
    return FormSchema.fromMap(data);
  }

  Future<ValidationResult> validateField({
    required String field,
    required dynamic value,
    required List<Map<String, dynamic>> rules,
    Map<String, dynamic> formData = const {},
  }) async {
    final payload = {
      'field': field,
      'value': value,
      'rules': rules,
      'form_data': formData,
    };
    final res = await _client.post<Map<String, dynamic>>('/forms/validate/', data: payload);
    final data = res.data ?? <String, dynamic>{};
    final valid = data['valid'] == true;
    final errors = (data['errors'] as List?)?.cast<String>() ?? const <String>[];
    return ValidationResult(valid: valid, errors: errors);
  }

  Future<Response<Map<String, dynamic>>> submit({
    required String formId,
    required String action,
    required Map<String, dynamic> data,
  }) {
    final payload = {
      'form_id': formId,
      'action': action,
      'data': data,
    };
    return _client.post<Map<String, dynamic>>('/forms/submit/', data: payload);
  }
}

class ValidationResult {
  final bool valid;
  final List<String> errors;
  const ValidationResult({required this.valid, this.errors = const []});
}

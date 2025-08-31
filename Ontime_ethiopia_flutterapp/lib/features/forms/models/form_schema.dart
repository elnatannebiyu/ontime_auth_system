import 'package:flutter/foundation.dart';

import 'field_schema.dart';

@immutable
class SubmitButton {
  final String text;
  final String? loadingText;
  const SubmitButton({required this.text, this.loadingText});

  factory SubmitButton.fromMap(Map<String, dynamic> json) => SubmitButton(
        text: (json['text'] ?? '').toString(),
        loadingText: json['loading_text']?.toString(),
      );
}

@immutable
class FormSchema {
  final String formId;
  final String? title;
  final String? description;
  final String action;
  final SubmitButton? submitButton;
  final List<FieldSchema> fields;
  final List<Map<String, dynamic>> links; // passthrough
  final Map<String, dynamic>? socialAuth; // passthrough
  final Map<String, dynamic>? metadata; // passthrough

  const FormSchema({
    required this.formId,
    required this.action,
    required this.fields,
    this.title,
    this.description,
    this.submitButton,
    this.links = const [],
    this.socialAuth,
    this.metadata,
  });

  factory FormSchema.fromMap(Map<String, dynamic> json) {
    return FormSchema(
      formId: (json['form_id'] ?? '').toString(),
      title: json['title']?.toString(),
      description: json['description']?.toString(),
      action: (json['action'] ?? '').toString(),
      submitButton: (json['submit_button'] is Map)
          ? SubmitButton.fromMap(
              (json['submit_button'] as Map).cast<String, dynamic>())
          : null,
      fields: (json['fields'] as List<dynamic>? ?? const [])
          .map((e) => FieldSchema.fromMap((e as Map).cast<String, dynamic>()))
          .toList(growable: false),
      links: (json['links'] as List<dynamic>? ?? const [])
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList(growable: false),
      socialAuth: (json['social_auth'] as Map?)?.cast<String, dynamic>(),
      metadata: (json['metadata'] as Map?)?.cast<String, dynamic>(),
    );
  }
}

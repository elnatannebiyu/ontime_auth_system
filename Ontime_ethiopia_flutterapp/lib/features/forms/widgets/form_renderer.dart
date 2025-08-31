import 'package:flutter/material.dart';

import '../models/form_schema.dart';
import '../models/field_schema.dart';
import '../validators/schema_validators.dart';

class FormRenderer extends StatefulWidget {
  final FormSchema schema;
  final void Function(Map<String, dynamic> values)? onChanged;
  final Future<void> Function(Map<String, dynamic> values)? onSubmit;

  const FormRenderer({super.key, required this.schema, this.onChanged, this.onSubmit});

  @override
  State<FormRenderer> createState() => _FormRendererState();
}

class _FormRendererState extends State<FormRenderer> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, dynamic> _values = {};
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    for (final f in widget.schema.fields) {
      _values[f.name] = f.defaultValue;
    }
  }

  void _setValue(String name, dynamic value) {
    setState(() {
      _values[name] = value;
    });
    widget.onChanged?.call(_values);
  }

  bool _shouldShow(FieldSchema field) {
    if (field.hidden) return false;
    final depends = field.dependsOn;
    if (depends != null && depends.isNotEmpty) {
      // simple conditional: compare equality if provided
      final logic = field.conditionalLogic ?? const {};
      if (logic.containsKey('equals')) {
        return _values[depends] == logic['equals'];
      }
      if (logic.containsKey('notEquals')) {
        return _values[depends] != logic['notEquals'];
      }
    }
    return true;
  }

  Widget _buildField(FieldSchema field) {
    final validator = SchemaValidators.compose(field);

    switch (field.type) {
      case FieldType.text:
      case FieldType.email:
      case FieldType.password:
      case FieldType.phone:
      case FieldType.otp:
      case FieldType.hidden:
        return _TextishField(
          field: field,
          value: (_values[field.name] ?? '').toString(),
          validator: (v) => validator(v, _values),
          onChanged: (v) => _setValue(field.name, v),
        );
      case FieldType.checkbox:
        return _CheckboxField(
          field: field,
          value: _values[field.name] == true,
          validator: (v) => validator(v, _values),
          onChanged: (v) => _setValue(field.name, v),
        );
      case FieldType.select:
        return _SelectField(
          field: field,
          value: _values[field.name],
          validator: (v) => validator(v, _values),
          onChanged: (v) => _setValue(field.name, v),
        );
      case FieldType.radio:
        return _RadioField(
          field: field,
          value: _values[field.name],
          validator: (v) => validator(v, _values),
          onChanged: (v) => _setValue(field.name, v),
        );
      case FieldType.date:
        return _DateField(
          field: field,
          value: _values[field.name],
          validator: (v) => validator(v, _values),
          onChanged: (v) => _setValue(field.name, v),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final visibleFields = widget.schema.fields.where(_shouldShow).toList();
    final submitText = widget.schema.submitButton?.text ?? 'Submit';

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.schema.title != null) ...[
            Text(widget.schema.title!, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
          ],
          if (widget.schema.description != null) ...[
            Text(widget.schema.description!, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 16),
          ],
          ...visibleFields.map((f) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: _buildField(f),
              )),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _submitting
                ? null
                : () async {
                    if (!_formKey.currentState!.validate()) return;
                    if (widget.onSubmit != null) {
                      setState(() => _submitting = true);
                      try {
                        await widget.onSubmit!.call(_values);
                      } finally {
                        if (mounted) setState(() => _submitting = false);
                      }
                    }
                  },
            child: Text(_submitting
                ? (widget.schema.submitButton?.loadingText ?? 'Submitting...')
                : submitText),
          ),
        ],
      ),
    );
  }
}

// --- Basic field implementations kept local to keep structure compact ---

class _TextishField extends StatelessWidget {
  final FieldSchema field;
  final String value;
  final String? Function(String?) validator;
  final ValueChanged<String> onChanged;

  const _TextishField({required this.field, required this.value, required this.validator, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final isPassword = field.type == FieldType.password;
    final keyboard = () {
      switch (field.type) {
        case FieldType.email:
          return TextInputType.emailAddress;
        case FieldType.phone:
          return TextInputType.phone;
        default:
          return TextInputType.text;
      }
    }();
    return TextFormField(
      initialValue: value,
      onChanged: onChanged,
      obscureText: isPassword,
      keyboardType: keyboard,
      decoration: InputDecoration(
        labelText: field.label ?? field.name,
        hintText: field.placeholder,
        helperText: field.helpText,
      ),
      validator: (v) => validator(v),
    );
  }
}

class _CheckboxField extends StatelessWidget {
  final FieldSchema field;
  final bool value;
  final String? Function(bool) validator;
  final ValueChanged<bool> onChanged;

  const _CheckboxField({required this.field, required this.value, required this.validator, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return FormField<bool>(
      initialValue: value,
      validator: (v) => validator(v ?? false),
      builder: (state) => CheckboxListTile(
        value: state.value ?? false,
        title: Text(field.label ?? field.name),
        subtitle: field.helpText != null ? Text(field.helpText!) : null,
        onChanged: (v) {
          state.didChange(v ?? false);
          onChanged(v ?? false);
        },
        controlAffinity: ListTileControlAffinity.leading,
        secondary: state.hasError ? Icon(Icons.error, color: Theme.of(context).colorScheme.error) : null,
      ),
    );
  }
}

class _SelectField extends StatelessWidget {
  final FieldSchema field;
  final dynamic value;
  final String? Function(dynamic) validator;
  final ValueChanged<dynamic> onChanged;

  const _SelectField({required this.field, required this.value, required this.validator, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final options = field.options ?? const [];
    return DropdownButtonFormField<dynamic>(
      value: value,
      items: [
        for (final opt in options)
          DropdownMenuItem(
            value: (opt is Map && opt.containsKey('value')) ? opt['value'] : opt,
            child: Text((opt is Map && opt.containsKey('label')) ? opt['label'].toString() : opt.toString()),
          )
      ],
      onChanged: onChanged,
      decoration: InputDecoration(labelText: field.label ?? field.name, helperText: field.helpText),
      validator: (v) => validator(v),
    );
  }
}

class _RadioField extends StatelessWidget {
  final FieldSchema field;
  final dynamic value;
  final String? Function(dynamic) validator;
  final ValueChanged<dynamic> onChanged;

  const _RadioField({required this.field, required this.value, required this.validator, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final options = field.options ?? const [];
    return FormField<dynamic>(
      initialValue: value,
      validator: (v) => validator(v),
      builder: (state) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (field.label != null) Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Text(field.label!, style: Theme.of(context).textTheme.bodyLarge),
          ),
          ...options.map((opt) {
            final val = (opt is Map && opt.containsKey('value')) ? opt['value'] : opt;
            final label = (opt is Map && opt.containsKey('label')) ? opt['label'].toString() : opt.toString();
            return RadioListTile<dynamic>(
              value: val,
              groupValue: state.value,
              title: Text(label),
              onChanged: (v) {
                state.didChange(v);
                onChanged(v);
              },
            );
          }),
          if (state.hasError)
            Padding(
              padding: const EdgeInsets.only(left: 16.0),
              child: Text(state.errorText!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            )
        ],
      ),
    );
  }
}

class _DateField extends StatefulWidget {
  final FieldSchema field;
  final String? value; // ISO-8601 or simple yyyy-MM-dd
  final String? Function(String?) validator;
  final ValueChanged<String?> onChanged;

  const _DateField({required this.field, required this.value, required this.validator, required this.onChanged});

  @override
  State<_DateField> createState() => _DateFieldState();
}

class _DateFieldState extends State<_DateField> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value ?? '');
  }

  @override
  void didUpdateWidget(covariant _DateField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _ctrl.text = widget.value ?? '';
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: _ctrl,
      readOnly: true,
      decoration: InputDecoration(
        labelText: widget.field.label ?? widget.field.name,
        hintText: widget.field.placeholder ?? 'Select date',
        suffixIcon: const Icon(Icons.calendar_today),
        helperText: widget.field.helpText,
      ),
      validator: widget.validator,
      onTap: () async {
        final now = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: now,
          firstDate: DateTime(1900),
          lastDate: DateTime(now.year + 10),
        );
        if (picked != null) {
          final iso = DateUtils.dateOnly(picked).toIso8601String().split('T').first;
          _ctrl.text = iso;
          widget.onChanged(iso);
        }
      },
    );
  }
}

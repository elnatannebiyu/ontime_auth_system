import 'package:flutter/material.dart';

import '../models/form_schema.dart';
import '../widgets/form_renderer.dart';
import '../services/form_service.dart';

class DynamicFormPage extends StatefulWidget {
  final String action;
  const DynamicFormPage({super.key, required this.action});

  @override
  State<DynamicFormPage> createState() => _DynamicFormPageState();
}

class _DynamicFormPageState extends State<DynamicFormPage> {
  late Future<FormSchema> _future;

  @override
  void initState() {
    super.initState();
    _future = FormService().fetchSchema(action: widget.action);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Form: ${widget.action}')),
      body: FutureBuilder<FormSchema>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          final schema = snapshot.data!;
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: SingleChildScrollView(
              child: FormRenderer(
                schema: schema,
                onSubmit: (values) async {
                  await FormService().submit(
                    formId: schema.formId,
                    action: schema.action,
                    data: values,
                  );
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Submitted successfully')),
                    );
                  }
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

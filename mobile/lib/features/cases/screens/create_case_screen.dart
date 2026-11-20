import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../case_controller.dart';

class CreateCaseScreen extends StatefulWidget {
  const CreateCaseScreen({super.key});

  @override
  State<CreateCaseScreen> createState() => _CreateCaseScreenState();
}

class _CreateCaseScreenState extends State<CreateCaseScreen> {
  final _formKey = GlobalKey<FormState>();
  String _selectedCategory = 'Academic Stress';
  final _phoneController = TextEditingController();
  final _matricController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _isSubmitting = false;

  final List<String> _categories = [
    'Academic Stress',
    'Personal Guidance',
    'Career Advice',
    'Mental Health',
    'Other',
  ];

  @override
  void dispose() {
    _phoneController.dispose();
    _matricController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      final summary =
          await context.read<CaseController>().createCase(
                phoneNumber: _phoneController.text.trim(),
                matricNumber: _matricController.text.trim(),
                category: _selectedCategory,
                description: _descriptionController.text.trim(),
              );

      if (!mounted) return;
      if (summary != null) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Prototype Crypto Summary'),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Case ID: ${summary.caseId}'),
                  Text('Case name: ${summary.caseName}'),
                  Text(
                    'Encrypted identity: ${summary.hasEncryptedIdentity ? 'present' : 'missing'}',
                  ),
                  Text(
                    'wrapped_key_A: ${summary.hasWrappedKeyA ? 'present' : 'missing'}',
                  ),
                  Text(
                    'shard_A: ${summary.hasShardA ? 'present' : 'missing'}',
                  ),
                  Text(
                    'wrapped_key_B: ${summary.hasWrappedKeyB ? 'present' : 'missing'}',
                  ),
                  Text(
                    'Committee shares: ${summary.committeeShareCount} encrypted',
                  ),
                  Text(
                    'shard_B: ${summary.shardBStored ? 'stored in secure storage' : 'not stored'}',
                  ),
                  const SizedBox(height: 12),
                  const Text('snake_case payload structure:'),
                  Text(summary.payloadStructure.toString()),
                  const SizedBox(height: 12),
                  const Text(
                    'Prototype/local-only: no live case endpoint is called.',
                  ),
                  const Text(
                    'Raw keys and ciphertext values are intentionally omitted.',
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop();
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Counselling Request'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Enrolled Phone Number',
                  hintText: 'e.g., 08012345678',
                  helperText:
                      'Encrypted on-device; only revealed with your consent or emergency quorum.',
                  border: OutlineInputBorder(),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Please enter your enrolled phone number';
                  }
                  if (val.trim().length < 10) {
                    return 'Please enter a valid phone number';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _matricController,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Registration Matric Number (prototype)',
                  hintText: 'e.g., U25CO0001',
                  helperText:
                      'Included in the locally encrypted prototype identity payload.',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter your matric number';
                  }
                  if (value.trim().length < 3) {
                    return 'Please enter a valid matric number';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _selectedCategory,
                decoration: const InputDecoration(
                  labelText: 'Category',
                  border: OutlineInputBorder(),
                ),
                items: _categories
                    .map((cat) => DropdownMenuItem(value: cat, child: Text(cat)))
                    .toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _selectedCategory = val);
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descriptionController,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Describe your situation',
                  hintText:
                      'Names, room numbers, and contact details are automatically scrubbed on-device...',
                  border: OutlineInputBorder(),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Please enter a description';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isSubmitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: _isSubmitting
                    ? const CircularProgressIndicator()
                    : const Text('Submit Request'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
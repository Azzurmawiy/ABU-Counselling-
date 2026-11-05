import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:local_auth/local_auth.dart';

import 'case_controller.dart';

class CasesListScreen extends StatefulWidget {
  const CasesListScreen({super.key});

  @override
  State<CasesListScreen> createState() => _CasesListScreenState();
}

class _CasesListScreenState extends State<CasesListScreen> {
  final LocalAuthentication _auth = LocalAuthentication();

  Future<void> _authenticateAndOpenCase(dynamic caseItem) async {
    try {
      final didAuthenticate = await _auth.authenticate(
        localizedReason:
            'Authenticate with biometrics or your device passcode to view this case',
        biometricOnly: false,
      );

      if (didAuthenticate && mounted) {
        _openCaseDetails(caseItem);
      }
    } on LocalAuthException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Device authentication failed. Set up biometrics or a screen lock to access cases.',
            ),
          ),
        );
      }
    }
  }

  void _openCaseDetails(dynamic caseItem) {
    Navigator.pushNamed(
      context,
      '/cases/details',
      arguments: caseItem,
    );
  }

  @override
  Widget build(BuildContext context) {
    final caseController = context.watch<CaseController>();
    final casesList = caseController.cases;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your Cases'),
      ),
      body: casesList.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('No cases found'),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pushNamed(context, '/cases/create');
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Add Your First Case'),
                  ),
                ],
              ),
            )
          : ListView.builder(
              itemCount: casesList.length,
              itemBuilder: (context, index) {
                final caseItem = casesList[index];

                // Safely extract pseudonym whether caseItem is a Map or an Object model
                final pseudonym = caseItem.pseudonym.isNotEmpty
                    ? caseItem.pseudonym
                    : 'Protected Case';
                return Card(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: ListTile(
                    leading: const CircleAvatar(
                      child: Icon(Icons.folder_open),
                    ),
                    // Displays the actual pseudonym (e.g. "Blue Sun") instead of "Case #1"
                    title: Text(
                      pseudonym,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    // Replaced raw caseItem.toString() with a privacy-compliant placeholder
                    subtitle:
                        const Text('Tap to authenticate and view details'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _authenticateAndOpenCase(caseItem),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.pushNamed(context, '/cases/create');
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}

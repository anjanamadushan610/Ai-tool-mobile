import 'package:flutter/material.dart';

import '../i18n.dart';
import '../state.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  String? _error;
  bool _busy = false;

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AppScope.read(context).login(_user.text.trim(), _pass.text);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(tr(context, 'app'), style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 8),
                Text(tr(context, 'signInHint')),
                const SizedBox(height: 24),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
                TextField(
                  controller: _user,
                  autocorrect: false,
                  textCapitalization: TextCapitalization.none,
                  autofillHints: const [AutofillHints.username],
                  decoration: InputDecoration(labelText: tr(context, 'username'), border: const OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _pass,
                  obscureText: true,
                  autofillHints: const [AutofillHints.password],
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(labelText: tr(context, 'password'), border: const OutlineInputBorder()),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: _busy
                        ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(tr(context, 'signIn')),
                  ),
                ),
                const SizedBox(height: 16),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'en', label: Text('English')),
                    ButtonSegment(value: 'si', label: Text('සිංහල')),
                  ],
                  selected: {s.locale.languageCode},
                  onSelectionChanged: (v) => s.setLanguage(v.first),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

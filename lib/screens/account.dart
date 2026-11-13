import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../i18n.dart';
import '../push.dart';
import '../state.dart';
import '../util.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final _cur = TextEditingController();
  final _new = TextEditingController();
  String _version = '';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((p) => setState(() => _version = '${p.version}+${p.buildNumber}'));
  }

  Future<void> _change() async {
    try {
      await AppScope.read(context).api.post('/auth/password', {'current': _cur.text, 'new': _new.text});
      _cur.clear();
      _new.clear();
      if (mounted) toast(context, tr(context, 'saved'));
    } catch (e) {
      if (mounted) toast(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final me = s.me!;
    return ListView(padding: const EdgeInsets.all(16), children: [
      ListTile(title: Text(tr(context, 'username')), subtitle: Text(me['username'] as String)),
      ListTile(title: Text(tr(context, 'role')), subtitle: Text(me['role'] as String)),
      ListTile(title: Text(tr(context, 'version')), subtitle: Text(_version)),
      ListTile(
        title: Text(tr(context, 'language')),
        trailing: SegmentedButton<String>(
          segments: const [ButtonSegment(value: 'en', label: Text('EN')), ButtonSegment(value: 'si', label: Text('සිං'))],
          selected: {s.locale.languageCode},
          onSelectionChanged: (v) => s.setLanguage(v.first),
        ),
      ),
      const Divider(),
      Text(tr(context, 'changePassword'), style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      TextField(controller: _cur, obscureText: true, decoration: InputDecoration(labelText: tr(context, 'currentPassword'))),
      TextField(controller: _new, obscureText: true, decoration: InputDecoration(labelText: tr(context, 'newPassword'))),
      const SizedBox(height: 12),
      FilledButton.tonal(onPressed: _change, child: Text(tr(context, 'changePassword'))),
      const Divider(height: 32),
      OutlinedButton.icon(
        icon: const Icon(Icons.logout),
        label: Text(tr(context, 'signOut')),
        onPressed: () async {
          await Push.unregister(s);
          await s.logout();
        },
      ),
    ]);
  }
}

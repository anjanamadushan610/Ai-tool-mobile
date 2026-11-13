import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../i18n.dart';
import '../state.dart';
import '../util.dart';

String newPassword() {
  const abc = 'abcdefghjkmnpqrstuvwxyzABCDEFGHJKMNPQRSTUVWXYZ23456789';
  final r = Random.secure();
  return List.generate(16, (_) => abc[r.nextInt(abc.length)]).join();
}

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  List<dynamic> _users = [];
  List<dynamic> _sessions = [];
  Map<String, dynamic>? _ws;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = AppScope.read(context).api;
    try {
      final u = await api.get('/users');
      final s = await api.get('/sessions');
      final w = await api.get('/workspaces');
      if (mounted) {
        setState(() {
          _users = u as List;
          _sessions = s as List;
          _ws = Map<String, dynamic>.from(w);
        });
      }
    } catch (e) {
      if (mounted) toast(context, e);
    }
  }

  Future<void> _showPassword(String username, String password) => showDialog(
        context: context,
        barrierDismissible: false,
        builder: (c) => AlertDialog(
          title: Text(tr(context, 'giveThese')),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            SelectableText('${tr(context, 'username')}: $username'),
            SelectableText('${tr(context, 'password')}: $password'),
          ]),
          actions: [
            TextButton(
              onPressed: () => Clipboard.setData(ClipboardData(text: '$username\n$password')),
              child: const Text('Copy'),
            ),
            FilledButton(onPressed: () => Navigator.pop(c), child: const Text('OK')),
          ],
        ),
      );

  Future<void> _edit([Map? u]) async {
    final api = AppScope.read(context).api;
    final username = TextEditingController();
    final name = TextEditingController(text: u?['display_name'] as String? ?? '');
    final repos = TextEditingController(text: ((u?['repos'] as List?) ?? const []).join('\n'));
    final limit = TextEditingController(text: u?['daily_budget_usd']?.toString() ?? '');
    var role = (u?['role'] as String?) ?? 'developer';
    final isOwnerRow = role == 'owner';
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(u == null ? tr(context, 'addStaff') : '${u['username']}'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (u == null) TextField(controller: username, decoration: InputDecoration(labelText: tr(context, 'username'))),
              TextField(controller: name, decoration: InputDecoration(labelText: tr(context, 'name'))),
              if (!isOwnerRow) ...[
                DropdownButtonFormField<String>(
                  initialValue: role,
                  decoration: InputDecoration(labelText: tr(context, 'role')),
                  items: const [
                    DropdownMenuItem(value: 'developer', child: Text('developer')),
                    DropdownMenuItem(value: 'viewer', child: Text('viewer')),
                  ],
                  onChanged: (v) => set(() => role = v ?? role),
                ),
                TextField(controller: repos, minLines: 2, maxLines: 6, decoration: InputDecoration(labelText: tr(context, 'reposHint'))),
                TextField(controller: limit, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr(context, 'dailyLimit'))),
              ],
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr(context, 'cancel'))),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr(context, u == null ? 'create' : 'save'))),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final repoList = repos.text.split(RegExp(r'[\n, ]+')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    try {
      if (u == null) {
        final pw = newPassword();
        await api.post('/users', {'username': username.text.trim(), 'display_name': name.text, 'role': role, 'password': pw, 'repos': repoList});
        if (mounted) await _showPassword(username.text.trim().toLowerCase(), pw);
      } else {
        final body = <String, dynamic>{'display_name': name.text};
        if (!isOwnerRow) {
          body['role'] = role;
          body['repos'] = repoList;
          body['daily_budget_usd'] = limit.text.trim().isEmpty ? null : double.tryParse(limit.text.trim());
        }
        await api.patch('/users/${u['id']}', body);
      }
      _load();
    } catch (e) {
      if (mounted) toast(context, e);
    }
  }

  Future<void> _reset(Map u) async {
    final pw = newPassword();
    try {
      await AppScope.read(context).api.post('/users/${u['id']}/password', {'password': pw});
      if (mounted) await _showPassword(u['username'] as String, pw);
      _load();
    } catch (e) {
      if (mounted) toast(context, e);
    }
  }

  Future<void> _toggle(Map u) async {
    try {
      await AppScope.read(context).api.patch('/users/${u['id']}', {'disabled': !(u['disabled'] as bool)});
      _load();
    } catch (e) {
      if (mounted) toast(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = AppScope.of(context).api;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.all(12), children: [
        FilledButton.icon(onPressed: () => _edit(), icon: const Icon(Icons.person_add_alt), label: Text(tr(context, 'addStaff'))),
        const SizedBox(height: 8),
        for (final u in _users)
          Card(
            child: ListTile(
              title: Text('${u['username']}${(u['display_name'] as String).isNotEmpty ? ' · ${u['display_name']}' : ''}',
                  style: TextStyle(decoration: u['disabled'] == true ? TextDecoration.lineThrough : null)),
              subtitle: Text('${u['role']} · ${((u['repos'] as List).isEmpty ? '—' : (u['repos'] as List).map((r) => '$r'.split('/').last).join(', '))}'),
              trailing: PopupMenuButton<String>(
                onSelected: (v) => v == 'edit' ? _edit(u) : v == 'pw' ? _reset(u) : _toggle(u),
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'edit', child: Text(tr(context, 'save'))),
                  PopupMenuItem(value: 'pw', child: Text(tr(context, 'resetPassword'))),
                  if (u['role'] != 'owner')
                    PopupMenuItem(value: 'toggle', child: Text(tr(context, u['disabled'] == true ? 'enable' : 'disable'))),
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),
        Text(tr(context, 'workspaces'), style: Theme.of(context).textTheme.titleMedium),
        for (final w in (_ws?['workspaces'] as List?) ?? const [])
          ListTile(
            dense: true,
            title: Text('${w['username']}'),
            subtitle: Text('${w['state']} · ${ago(w['last_active'] as String?)}'),
            trailing: w['state'] == 'running'
                ? TextButton(
                    onPressed: () async {
                      final u = _users.firstWhere((x) => x['username'] == w['username']);
                      await api.post('/workspaces/${u['id']}/stop');
                      _load();
                    },
                    child: Text(tr(context, 'stopWorkspace')))
                : null,
          ),
        const SizedBox(height: 12),
        Text(tr(context, 'sessions'), style: Theme.of(context).textTheme.titleMedium),
        for (final s in _sessions)
          ListTile(
            dense: true,
            title: Text('${s['username']} · ${s['ip']}'),
            subtitle: Text("${'${s['user_agent']}'.split(' ').take(3).join(' ')} · ${ago(s['last_seen'] as String?)}"),
            trailing: TextButton(
              onPressed: () async {
                await api.delete('/sessions/${s['id']}');
                _load();
              },
              child: Text(tr(context, 'signOutDevice')),
            ),
          ),
      ]),
    );
  }
}

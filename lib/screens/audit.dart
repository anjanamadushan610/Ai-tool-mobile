import 'package:flutter/material.dart';

import '../i18n.dart';
import '../state.dart';
import '../util.dart';

/// Who did what, newest first. The owner sees everyone; a developer sees only their own rows
/// (the server enforces this, the screen just shows what it gets).
class AuditScreen extends StatefulWidget {
  const AuditScreen({super.key});

  @override
  State<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends State<AuditScreen> {
  final List<dynamic> _rows = [];
  bool _loading = false;
  bool _more = true;
  String? _err;

  static const _colors = {
    'login.failed': Colors.red,
    'login.locked': Colors.deepOrange,
    'login.ok': Colors.green,
    'session.killed': Colors.orange,
    'approval.allowed': Colors.green,
    'approval.denied': Colors.red,
    'workspace.refused': Colors.orange,
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool older = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      final before = older && _rows.isNotEmpty ? '&before_id=${_rows.last['id']}' : '';
      final page = (await AppScope.read(context).api.get('/audit?limit=100$before')) as List;
      if (!mounted) return;
      setState(() {
        if (!older) _rows.clear();
        _rows.addAll(page);
        _more = page.length == 100;
      });
    } catch (e) {
      if (mounted) setState(() => _err = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _rows.length + 1,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, i) {
          if (i == _rows.length) {
            if (_err != null) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Column(children: [
                  Text(_err!, style: TextStyle(color: theme.colorScheme.error)),
                  TextButton(onPressed: _load, child: Text(tr(context, 'retry'))),
                ]),
              );
            }
            if (_loading) return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
            if (_rows.isEmpty) return Padding(padding: const EdgeInsets.all(24), child: Center(child: Text(tr(context, 'noAudit'))));
            return _more
                ? Padding(
                    padding: const EdgeInsets.all(12),
                    child: OutlinedButton(onPressed: () => _load(older: true), child: Text(tr(context, 'loadOlder'))),
                  )
                : const SizedBox(height: 24);
          }
          final a = _rows[i];
          final action = '${a['action']}';
          final color = _colors[action];
          final detail = '${a['detail'] ?? ''}';
          return ListTile(
            dense: true,
            title: Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  border: Border.all(color: color ?? theme.dividerColor),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(action, style: const TextStyle(fontSize: 12)),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text('${a['username']}', overflow: TextOverflow.ellipsis)),
            ]),
            subtitle: Text(
              [
                fmt(a['at'] as String),
                if ('${a['target'] ?? ''}'.isNotEmpty) '${a['target']}',
                if (detail.isNotEmpty) detail,
                if ('${a['ip'] ?? ''}'.isNotEmpty) '${a['ip']}',
              ].join(' · '),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          );
        },
      ),
    );
  }
}

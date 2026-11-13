import 'dart:async';

import 'package:flutter/material.dart';

import '../attach.dart';
import '../i18n.dart';
import '../push.dart';
import '../state.dart';
import '../util.dart';
import 'task_view.dart';

const ownerFolders = [
  'SRIBEESonline/fastapi_backend', 'SRIBEESonline/admin', 'SRIBEESonline/mobile', 'SRIBEESonline/partner-portal',
  'SRIBEESonline/ecommerce-frontend', 'SribeesExpress/backend-fastapi', 'SribeesExpress/rider-app', 'Ai-tool',
  '810/Sribees-Online-Finance-Backend', '810/Sribees-Online-Base-Price-Backend', '810/Sribees-Price-Intel-Backend',
  '810/Sribees-Price', '810/Sribees-Online-NewOrder-App',
];

void openTask(BuildContext context, int id) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => TaskViewScreen(id: id)));

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  List<dynamic> _rows = [];
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _load());
    WidgetsBinding.instance.addPostFrameCallback((_) => Push.register(AppScope.read(context)));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await AppScope.read(context).api.get('/tasks');
      if (mounted) setState(() => _rows = r as List);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.all(12), children: [
        if (!s.isOwner && s.can('workspace.open')) const WorkspaceCard(),
        if (s.can('tasks.start')) const NewTaskCard(),
        const SizedBox(height: 8),
        if (_rows.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Center(child: Text(tr(context, 'noTasks')))),
        for (final t in _rows)
          Card(
            child: ListTile(
              title: Text(t['title'] as String, maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text('${t['username']} · ${t['repo']} · ${fmt(t['created_at'] as String)}'),
              trailing: statusChip(t['status'] as String),
              onTap: () => openTask(context, t['id'] as int),
            ),
          ),
      ]),
    );
  }
}

class NewTaskCard extends StatefulWidget {
  const NewTaskCard({super.key});

  @override
  State<NewTaskCard> createState() => _NewTaskCardState();
}

class _NewTaskCardState extends State<NewTaskCard> {
  final _prompt = TextEditingController();
  final _attach = Attachments();
  String? _repo;
  bool _busy = false;

  Future<void> _start() async {
    final s = AppScope.read(context);
    if (_repo == null || _prompt.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      final t = await s.api.post('/tasks', {'repo': _repo, 'prompt': _prompt.text, 'attachments': _attach.ids});
      _prompt.clear();
      _attach.clear();
      if (mounted) openTask(context, t['id'] as int);
    } catch (e) {
      if (mounted) toast(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final options = s.isOwner ? ownerFolders : ((s.me?['repos'] as List?) ?? const []).cast<String>();
    _repo ??= options.isNotEmpty ? options.first : null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(tr(context, 'newTask'), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _repo,
            isExpanded: true,
            decoration: InputDecoration(labelText: tr(context, s.isOwner ? 'folder' : 'repo')),
            items: [for (final o in options) DropdownMenuItem(value: o, child: Text(o, overflow: TextOverflow.ellipsis))],
            onChanged: (v) => setState(() => _repo = v),
          ),
          TextField(
            controller: _prompt,
            minLines: 2,
            maxLines: 8,
            decoration: InputDecoration(labelText: tr(context, 'prompt')),
          ),
          AttachRow(attachments: _attach),
          FilledButton.icon(
            onPressed: _busy ? null : _start,
            icon: const Icon(Icons.rocket_launch_outlined),
            label: Text(tr(context, 'start')),
          ),
        ]),
      ),
    );
  }
}

class WorkspaceCard extends StatefulWidget {
  const WorkspaceCard({super.key});

  @override
  State<WorkspaceCard> createState() => _WorkspaceCardState();
}

class _WorkspaceCardState extends State<WorkspaceCard> {
  Map<String, dynamic>? _ws;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await AppScope.read(context).api.get('/workspace');
      if (mounted) setState(() => _ws = Map<String, dynamic>.from(r));
    } catch (_) {}
  }

  Future<void> _act(String what) async {
    setState(() => _busy = true);
    try {
      final r = await AppScope.read(context).api.post('/workspace/$what');
      setState(() => _ws = Map<String, dynamic>.from(r));
    } catch (e) {
      if (mounted) toast(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final running = _ws?['state'] == 'running';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(tr(context, 'myWorkspace'), style: Theme.of(context).textTheme.titleMedium)),
            if (_ws != null) Chip(label: Text(_ws!['state'] as String)),
          ]),
          Text(tr(context, 'workspaceHint'), style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          running
              ? OutlinedButton(onPressed: _busy ? null : () => _act('stop'), child: Text(tr(context, 'stopWorkspace')))
              : FilledButton(onPressed: _busy ? null : () => _act('start'), child: Text(tr(context, 'startWorkspace'))),
        ]),
      ),
    );
  }
}

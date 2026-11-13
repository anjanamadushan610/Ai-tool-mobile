import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../attach.dart';
import '../i18n.dart';
import '../state.dart';
import '../util.dart';

const _active = {'queued', 'running'};

String toolSummary(String name, Map input) {
  if (name == 'Bash') return '${input['command'] ?? ''}';
  for (final k in ['file_path', 'notebook_path', 'pattern', 'url']) {
    if (input[k] != null) return '${input[k]}';
  }
  final s = jsonEncode(input);
  return s.length > 160 ? '${s.substring(0, 160)}…' : s;
}

String _resultText(dynamic c) {
  if (c is String) return c;
  if (c is List) return c.map((x) => x is Map && x['type'] == 'text' ? x['text'] : '[${x is Map ? x['type'] : '?'}]').join('\n');
  return jsonEncode(c);
}

class TaskViewScreen extends StatefulWidget {
  const TaskViewScreen({super.key, required this.id});
  final int id;

  @override
  State<TaskViewScreen> createState() => _TaskViewScreenState();
}

class _TaskViewScreenState extends State<TaskViewScreen> {
  Map<String, dynamic>? _task;
  final List<Map<String, dynamic>> _events = [];
  int _last = 0;
  Timer? _timer;
  final _text = TextEditingController();
  final _scroll = ScrollController();
  final _attach = Attachments();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _tick();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _tick() async {
    var delay = const Duration(seconds: 5);
    try {
      final api = AppScope.read(context).api;
      final t = Map<String, dynamic>.from(await api.get('/tasks/${widget.id}'));
      final ev = (await api.get('/tasks/${widget.id}/events?after=$_last')) as List;
      if (!mounted) return;
      setState(() {
        _task = t;
        for (final e in ev) {
          _events.add(Map<String, dynamic>.from(e));
        }
        if (ev.isNotEmpty) _last = ev.last['id'] as int;
      });
      if (ev.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
        });
      }
      if (_active.contains(t['status'])) delay = const Duration(milliseconds: 1200);
    } catch (_) {}
    if (mounted) _timer = Timer(delay, _tick);
  }

  Future<void> _decide(Map a, bool allow) async {
    try {
      await AppScope.read(context).api.post('/tasks/${widget.id}/approvals/${a['id']}', {'allow': allow});
    } catch (e) {
      if (mounted) toast(context, e);
    }
  }

  Future<void> _send() async {
    if (_text.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      await AppScope.read(context).api.post('/tasks/${widget.id}/messages', {'prompt': _text.text, 'attachments': _attach.ids});
      _text.clear();
      _attach.clear();
      _timer?.cancel();
      _tick();
    } catch (e) {
      if (mounted) toast(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop() async {
    try {
      await AppScope.read(context).api.post('/tasks/${widget.id}/stop');
    } catch (e) {
      if (mounted) toast(context, e);
    }
  }

  Widget _event(Map<String, dynamic> e) {
    final d = e['data'] as Map;
    final theme = Theme.of(context);
    switch (e['kind']) {
      case 'prompt':
        return Align(
          alignment: Alignment.centerRight,
          child: Card(
            color: theme.colorScheme.primaryContainer,
            child: Padding(padding: const EdgeInsets.all(10), child: SelectableText('${d['text']}')),
          ),
        );
      case 'status':
        return Text('— ${d['status']}${d['by'] != null ? ' · ${d['by']}' : ''} · ${fmt(e['at'] as String)}',
            style: theme.textTheme.bodySmall);
      case 'error':
        return Text('${d['message']}', style: TextStyle(color: theme.colorScheme.error));
      case 'approval':
        return Text('${d['status']} · ${d['tool']}${d['by'] != null ? ' · ${d['by']}' : ''}', style: theme.textTheme.bodySmall);
      case 'git':
        return Text(
          '${d['ok'] == true ? (d['pushed'] == true ? 'pushed' : 'committed') : 'git failed'} · ${d['branch']} · ${d['files']} file(s) · “${d['message']}” · ${d['by']}',
          style: theme.textTheme.bodySmall?.copyWith(color: d['ok'] == true ? Colors.green : theme.colorScheme.error),
        );
    }
    if (d['type'] == 'assistant') {
      final parts = ((d['message'] as Map?)?['content'] as List?) ?? const [];
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final c in parts)
          if (c['type'] == 'text')
            SelectableText('${c['text']}')
          else if (c['type'] == 'tool_use')
            Container(
              margin: const EdgeInsets.symmetric(vertical: 2),
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(6)),
              child: SelectableText('${c['name']}: ${toolSummary('${c['name']}', (c['input'] as Map?) ?? {})}',
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
            ),
      ]);
    }
    if (d['type'] == 'user') {
      final results = (((d['message'] as Map?)?['content'] as List?) ?? const []).where((c) => c['type'] == 'tool_result');
      return Column(children: [
        for (final r in results)
          ExpansionTile(
            dense: true,
            tilePadding: EdgeInsets.zero,
            title: Text(tr(context, r['is_error'] == true ? 'toolError' : 'toolOutput'), style: theme.textTheme.bodySmall),
            children: [
              SelectableText(() {
                final t = _resultText(r['content']);
                return t.length > 6000 ? '${t.substring(0, 6000)}…' : t;
              }(), style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
            ],
          ),
      ]);
    }
    if (d['type'] == 'result') {
      final cost = (d['total_cost_usd'] as num?)?.toDouble() ?? 0;
      return Text('${tr(context, 'finished')} · ${d['num_turns'] ?? '?'} turns · ${((d['duration_ms'] as num? ?? 0) / 1000).round()} s · USD ${cost.toStringAsFixed(4)}',
          style: theme.textTheme.bodySmall);
    }
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    final t = _task;
    final s = AppScope.of(context);
    if (t == null) return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    final active = _active.contains(t['status']);
    final mine = t['username'] == s.me?['username'] || s.isOwner;
    final pending = (t['pending_approvals'] as List?) ?? const [];
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(t['title'] as String, maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: [
            Center(child: statusChip(t['status'] as String)),
            if (active && mine) IconButton(onPressed: _stop, icon: const Icon(Icons.stop_circle_outlined), tooltip: tr(context, 'stop')),
          ],
          bottom: TabBar(tabs: [Tab(text: tr(context, 'conversation')), Tab(text: tr(context, 'changes'))]),
        ),
        body: TabBarView(children: [
          Column(children: [
            Expanded(
              child: ListView(controller: _scroll, padding: const EdgeInsets.all(12), children: [
                Text('${t['repo']} · ${t['username']} · USD ${(t['cost_usd'] as num).toStringAsFixed(4)}',
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 8),
                for (final e in _events) Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: _event(e)),
                for (final a in pending)
                  Card(
                    color: Colors.amber.withValues(alpha: 0.18),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${tr(context, 'wantsToUse')} ${a['tool']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 6),
                        SelectableText(toolSummary('${a['tool']}', (a['input'] as Map?) ?? {}),
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                        if (mine)
                          Row(children: [
                            FilledButton.icon(onPressed: () => _decide(a, true), icon: const Icon(Icons.check), label: Text(tr(context, 'allow'))),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(onPressed: () => _decide(a, false), icon: const Icon(Icons.close), label: Text(tr(context, 'deny'))),
                          ]),
                      ]),
                    ),
                  ),
                if (active && pending.isEmpty)
                  Padding(padding: const EdgeInsets.all(8), child: Row(children: [
                    const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: 8),
                    Text(tr(context, 'stillWorking')),
                  ])),
              ]),
            ),
            if (mine)
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    AttachRow(attachments: _attach, enabled: !active),
                    Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _text,
                        enabled: !active,
                        minLines: 1,
                        maxLines: 5,
                        decoration: InputDecoration(hintText: tr(context, active ? 'stillWorking' : 'followUp'), border: const OutlineInputBorder()),
                      ),
                    ),
                    IconButton.filled(onPressed: active || _busy ? null : _send, icon: const Icon(Icons.send)),
                    ]),
                  ]),
                ),
              ),
          ]),
          _DiffView(id: widget.id, active: active, canPush: mine && s.can('git.push_staff')),
        ]),
      ),
    );
  }
}

class _DiffView extends StatefulWidget {
  const _DiffView({required this.id, required this.active, required this.canPush});
  final int id;
  final bool active;
  final bool canPush;

  @override
  State<_DiffView> createState() => _DiffViewState();
}

class _DiffViewState extends State<_DiffView> {
  Map<String, dynamic>? _d;
  Map<String, dynamic>? _git;
  Set<String> _picked = {};
  final _msg = TextEditingController();
  bool _busy = false;
  String? _err;
  String? _gitOut;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = AppScope.read(context).api;
    try {
      final d = Map<String, dynamic>.from(await api.get('/tasks/${widget.id}/diff'));
      final g = Map<String, dynamic>.from(await api.get('/tasks/${widget.id}/git'));
      if (!mounted) return;
      setState(() {
        _d = d;
        _git = g;
        _picked = {for (final f in (g['files'] as List)) '${f['path']}'};
      });
    } catch (e) {
      if (mounted) setState(() => _err = e.toString());
    }
  }

  Future<void> _commit(bool push) async {
    setState(() {
      _busy = true;
      _gitOut = null;
    });
    try {
      final r = await AppScope.read(context).api.post('/tasks/${widget.id}/commit',
          {'message': _msg.text, 'files': _picked.toList(), 'push': push});
      if (!mounted) return;
      if (r['ok'] == true) {
        toast(context, push ? '${tr(context, 'pushedTo')} ${r['branch']}' : tr(context, 'committed'));
        _msg.clear();
      } else {
        setState(() => _gitOut = [for (final s in (r['steps'] as List)) '\$ git ${s['step']}\n${s['output']}'].join('\n'));
      }
      _load();
    } catch (e) {
      if (mounted) toast(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _commitPanel() {
    final g = _git!;
    final files = (g['files'] as List);
    final branch = '${g['branch']}';
    final protectedBranch = branch == 'main' || branch == 'master';
    final ready = _msg.text.trim().isNotEmpty && _picked.isNotEmpty && !_busy;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('${tr(context, 'commit')} · $branch${g['ahead'] != null && g['ahead'] > 0 ? ' · ${g['ahead']} not pushed' : ''}',
              style: Theme.of(context).textTheme.titleSmall),
          if (protectedBranch) Text(tr(context, 'mainBlocked'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
          if (files.isEmpty) Text(tr(context, 'nothingToCommit')),
          for (final f in files)
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: _picked.contains('${f['path']}'),
              onChanged: (v) => setState(() => v == true ? _picked.add('${f['path']}') : _picked.remove('${f['path']}')),
              title: Text('${f['status']}  ${f['path']}', style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
            ),
          if (widget.canPush && !protectedBranch && files.isNotEmpty) ...[
            TextField(
              controller: _msg,
              onChanged: (_) => setState(() {}),
              minLines: 1,
              maxLines: 4,
              decoration: InputDecoration(labelText: tr(context, 'commitMessage')),
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              OutlinedButton(onPressed: ready ? () => _commit(false) : null, child: Text(tr(context, 'commit'))),
              FilledButton(onPressed: ready ? () => _commit(true) : null, child: Text('${tr(context, 'commitPush')} → $branch')),
            ]),
          ],
          if (_gitOut != null)
            SelectableText(_gitOut!, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_err != null) return Center(child: Text(_err!));
    if (_d == null) return const Center(child: CircularProgressIndicator());
    final diff = '${_d!['diff']}';
    if (diff.isEmpty && '${_d!['status']}'.trim().isEmpty) return Center(child: Text(tr(context, 'noChanges')));
    return ListView(padding: const EdgeInsets.all(12), children: [
      if (!widget.active && _git != null) _commitPanel(),
      SelectableText('${_d!['status']}', style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
      const Divider(),
      for (final l in diff.split('\n'))
        Text(l, style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 11,
          color: l.startsWith('+') && !l.startsWith('+++') ? Colors.green.shade700 : l.startsWith('-') && !l.startsWith('---') ? Colors.red.shade700 : null,
        )),
    ]);
  }
}

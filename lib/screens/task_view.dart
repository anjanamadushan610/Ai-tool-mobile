import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

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
      await AppScope.read(context).api.post('/tasks/${widget.id}/messages', {'prompt': _text.text});
      _text.clear();
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
                  child: Row(children: [
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
                ),
              ),
          ]),
          _DiffView(id: widget.id),
        ]),
      ),
    );
  }
}

class _DiffView extends StatefulWidget {
  const _DiffView({required this.id});
  final int id;

  @override
  State<_DiffView> createState() => _DiffViewState();
}

class _DiffViewState extends State<_DiffView> {
  Map<String, dynamic>? _d;
  String? _err;

  @override
  void initState() {
    super.initState();
    AppScope.read(context).api.get('/tasks/${widget.id}/diff').then((r) {
      if (mounted) setState(() => _d = Map<String, dynamic>.from(r));
    }).catchError((Object e) {
      if (mounted) setState(() => _err = e.toString());
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_err != null) return Center(child: Text(_err!));
    if (_d == null) return const Center(child: CircularProgressIndicator());
    final diff = '${_d!['diff']}';
    if (diff.isEmpty && '${_d!['status']}'.trim().isEmpty) return Center(child: Text(tr(context, 'noChanges')));
    return ListView(padding: const EdgeInsets.all(12), children: [
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

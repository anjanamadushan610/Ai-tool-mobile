import 'dart:async';

import 'package:flutter/material.dart';

import '../i18n.dart';
import '../state.dart';
import '../util.dart';
import 'report.dart';

class ServerScreen extends StatefulWidget {
  const ServerScreen({super.key});

  @override
  State<ServerScreen> createState() => _ServerScreenState();
}

class _ServerScreenState extends State<ServerScreen> {
  Map<String, dynamic>? _ov;
  List<dynamic> _hist = [];
  List<dynamic> _cont = [];
  Map<String, dynamic>? _report;
  String? _err;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final api = AppScope.read(context).api;
    try {
      final ov = await api.get('/admin/overview');
      final hist = await api.get('/admin/history?hours=24');
      if (!mounted) return;
      setState(() {
        _ov = Map<String, dynamic>.from(ov);
        _hist = hist as List;
        _err = null;
      });
      final c = await api.get('/admin/containers');
      if (mounted) setState(() => _cont = c as List);
      final reps = (await api.get('/admin/reports?limit=1')) as List;
      if (mounted) setState(() => _report = reps.isEmpty ? null : Map<String, dynamic>.from(reps.first));
    } catch (e) {
      if (mounted) setState(() => _err = e.toString());
    }
  }

  Widget _tile(String title, String value, String sub) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: Theme.of(context).textTheme.bodySmall),
            Text(value, style: Theme.of(context).textTheme.headlineSmall),
            Text(sub, style: Theme.of(context).textTheme.bodySmall, maxLines: 2),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final host = _ov?['host'] as Map?;
    final cs = Theme.of(context).colorScheme;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.all(12), children: [
        if (_err != null) Text(_err!, style: TextStyle(color: cs.error)),
        if (_report != null)
          ReportCard(
            report: _report!,
            compact: true,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ReportScreen())),
          )
        else
          TextButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ReportScreen())),
            icon: const Icon(Icons.wb_sunny_outlined),
            label: Text(tr(context, 'morningReport')),
          ),
        if (host != null)
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.7,
            children: [
              _tile(tr(context, 'memory'), '${host['memory']['used_pct']}%', '${host['memory']['available_mb']} MB ${tr(context, 'freeOf')} ${((host['memory']['total_mb'] as num) / 1024).round()} GB'),
              _tile(tr(context, 'cpu'), host['cpu_pct'] == null ? '—' : '${host['cpu_pct']}%', '${host['load']['cpus']} cores'),
              _tile(tr(context, 'load'), '${host['load']['load1']}', '5m ${host['load']['load5']} · 15m ${host['load']['load15']}'),
              _tile(tr(context, 'disk'), '${host['disk']['used_pct']}%', '${host['disk']['free_gb']} GB ${tr(context, 'freeOf')} ${host['disk']['total_gb']} GB'),
            ],
          ),
        const SizedBox(height: 8),
        Text(tr(context, 'health'), style: Theme.of(context).textTheme.titleMedium),
        for (final h in (_ov?['health'] as List?) ?? const [])
          ListTile(
            dense: true,
            leading: Icon(
              h['ok'] == true ? Icons.check_circle : h['ok'] == false ? Icons.cancel : Icons.help,
              color: h['ok'] == true ? Colors.green : h['ok'] == false ? cs.error : Colors.grey,
            ),
            title: Text('${h['name']}'),
            subtitle: Text(h['ok'] == true
                ? '${tr(context, 'up')} · ${h['ms']} ms · 24h ${h['uptime_24h'] ?? '—'}%'
                : h['ok'] == false
                    ? '${tr(context, 'down')} (${h['status']}) · 24h ${h['uptime_24h'] ?? '—'}%'
                    : tr(context, 'notChecked')),
          ),
        const SizedBox(height: 8),
        _Spark(title: '${tr(context, 'memory')} (%) · 24h', values: [for (final p in _hist) (p['mem_used_pct'] as num).toDouble()], max: 100),
        _Spark(title: '${tr(context, 'cpu')} (%) · 24h', values: [for (final p in _hist) if (p['cpu_pct'] != null) (p['cpu_pct'] as num).toDouble()], max: 100),
        const SizedBox(height: 8),
        Text(tr(context, 'containers'), style: Theme.of(context).textTheme.titleMedium),
        for (final c in _cont.take(12))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text('${c['name']}', style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
                Text('${(c['mem_mb'] as num).round()} MB', style: const TextStyle(fontSize: 12)),
              ]),
              LinearProgressIndicator(
                value: _cont.isEmpty ? 0 : (c['mem_mb'] as num) / (_cont.first['mem_mb'] as num),
                minHeight: 5,
                borderRadius: BorderRadius.circular(4),
              ),
            ]),
          ),
        const SizedBox(height: 12),
        Text(tr(context, 'cost'), style: Theme.of(context).textTheme.titleMedium),
        for (final c in (_ov?['cost'] as List?) ?? const [])
          ListTile(
            dense: true,
            title: Text('${c['username']}'),
            subtitle: Text('${tr(context, 'today')}: ${(c['today_usd'] as num).toStringAsFixed(3)} · ${tr(context, 'month')}: ${(c['month_usd'] as num).toStringAsFixed(3)}'),
          ),
        if (_ov != null) Text(fmt(_ov!['generated_at'] as String), style: Theme.of(context).textTheme.bodySmall),
      ]),
    );
  }
}

/// A small single-series area chart with a 0..max scale. One series per chart, never two axes.
class _Spark extends StatelessWidget {
  const _Spark({required this.title, required this.values, required this.max});
  final String title;
  final List<double> values;
  final double max;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).brightness == Brightness.dark ? const Color(0xFF7AA7D9) : const Color(0xFF3A6EA5);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(title, style: Theme.of(context).textTheme.bodySmall)),
            if (values.isNotEmpty) Text('${values.last.round()}%', style: Theme.of(context).textTheme.titleSmall),
          ]),
          const SizedBox(height: 6),
          SizedBox(
            height: 80,
            width: double.infinity,
            child: values.length < 2
                ? const Center(child: Text('…'))
                : CustomPaint(painter: _SparkPainter(values, max, color, Theme.of(context).dividerColor)),
          ),
        ]),
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.v, this.max, this.color, this.grid);
  final List<double> v;
  final double max;
  final Color color;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    final g = Paint()..color = grid..strokeWidth = 1;
    for (final f in [0.0, 0.5, 1.0]) {
      canvas.drawLine(Offset(0, size.height * f), Offset(size.width, size.height * f), g);
    }
    final path = Path();
    for (var i = 0; i < v.length; i++) {
      final x = size.width * i / (v.length - 1);
      final y = size.height * (1 - (v[i] / max).clamp(0, 1));
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    final area = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(area, Paint()..color = color.withValues(alpha: 0.16));
    canvas.drawPath(path, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 2..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) => old.v != v;
}

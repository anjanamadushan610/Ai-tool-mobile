import 'package:flutter/material.dart';

import '../i18n.dart';
import '../state.dart';
import '../util.dart';

/// Morning reports (owner): yesterday's prod health, errors and Claude cost. Newest first.
class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  List<dynamic>? _rows;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await AppScope.read(context).api.get('/admin/reports?limit=14');
      if (mounted) setState(() => _rows = r as List);
    } catch (e) {
      if (mounted) toast(context, e);
    }
  }

  Future<void> _sendNow() async {
    setState(() => _busy = true);
    try {
      await AppScope.read(context).api.post('/admin/reports/send');
      await _load();
    } catch (e) {
      if (mounted) toast(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'morningReport')), actions: [
        TextButton(onPressed: _busy ? null : _sendNow, child: Text(tr(context, 'sendNow'))),
      ]),
      body: _rows == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.all(12), children: [
                if (_rows!.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Text(tr(context, 'noReports'))),
                for (final r in _rows!) ReportCard(report: Map<String, dynamic>.from(r)),
              ]),
            ),
    );
  }
}

class ReportCard extends StatelessWidget {
  const ReportCard({super.key, required this.report, this.compact = false, this.onTap});
  final Map<String, dynamic> report;
  final bool compact;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final r = report;
    final services = (r['services'] as List?) ?? const [];
    final down = (r['services_down'] as num?) ?? 0;
    final tasks = Map<String, dynamic>.from(r['tasks'] as Map? ?? {});
    final server = Map<String, dynamic>.from(r['server'] as Map? ?? {});
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(down == 0 ? Icons.check_circle : Icons.warning_amber, color: down == 0 ? Colors.green : Colors.orange),
              const SizedBox(width: 8),
              Expanded(child: Text('${tr(context, 'morningReport')} · ${r['date']}', style: t.titleSmall)),
            ]),
            const SizedBox(height: 6),
            Text(down == 0
                ? '${tr(context, 'allUp')} (${services.length})'
                : '$down ${tr(context, 'servicesFailed')}'),
            if (!compact)
              for (final s in services)
                Text('• ${s['name']}: ${s['uptime'] ?? '—'}%${(s['failed'] ?? 0) > 0 ? ' (${s['failed']} ${tr(context, 'failedChecks')})' : ''}',
                    style: t.bodySmall),
            const SizedBox(height: 6),
            Text('${tr(context, 'tasks')}: ${tasks['total'] ?? 0} · ${tr(context, 'failed')}: ${tasks['failed'] ?? 0}'
                '${(tasks['interrupted'] ?? 0) > 0 ? ' · interrupted: ${tasks['interrupted']}' : ''}'),
            Text('Claude: \$${((r['cost_yesterday'] as num?) ?? 0).toStringAsFixed(2)} · ${tr(context, 'month')}: \$${((r['cost_month'] as num?) ?? 0).toStringAsFixed(2)}'),
            Text('RAM ${server['mem_used_pct'] ?? '—'}% (peak ${server['peak_mem_pct'] ?? '—'}%) · Disk ${server['disk_used_pct'] ?? '—'}%',
                style: t.bodySmall),
            if ((r['failed_logins'] ?? 0) > 0)
              Text('${r['failed_logins']} ${tr(context, 'failedLogins')}', style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ]),
        ),
      ),
    );
  }
}
